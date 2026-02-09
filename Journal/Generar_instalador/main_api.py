import MetaTrader5 as mt5
import logging
from flask import Flask, request, jsonify
from functools import wraps
import os
import sys
import json
import psutil
import time
import threading
from datetime import datetime, timedelta
from waitress import serve

# --- NUEVAS IMPORTACIONES PARA EL ICONO ---
import pystray
from pystray import MenuItem as item
from PIL import Image, ImageDraw

# --- CONFIGURACIÓN ---
def load_config():
    if getattr(sys, 'frozen', False):
        app_path = os.path.dirname(sys.executable)
    else:
        app_path = os.path.dirname(os.path.abspath(__file__))
    
    config_path = os.path.join(app_path, 'config.json')
    
    # Valores por defecto
    default_config = {
        #"mt5_path": r"C:\Program Files\MT5-history\terminal64.exe",
        "mt5_path": r"C:\Users\Administrator\Documents\MT5-portable\terminal64.exe",
        "port": 5000,
        "api_key": "clave_default_dev"
    }

    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            return json.load(f)
    return default_config

config = load_config()

PATH_MT5 = config.get('mt5_path')
PROCESS_NAME = "terminal64.exe"
PORT = int(config.get('port', 5000))
API_KEY_SECRET = config.get('api_key')

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - API - %(message)s')

# --- SEGURIDAD ---
def require_api_key(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('X-API-KEY')
        if not token or token != API_KEY_SECRET:
            return jsonify({"status": "error", "message": "Acceso Denegado"}), 401
        return f(*args, **kwargs)
    return decorated_function

# --- GESTIÓN DE PROCESOS (MODO FRANCOTIRADOR) ---
def is_specific_mt5_running():
    target_path = os.path.normpath(PATH_MT5).lower()
    for proc in psutil.process_iter(['name', 'exe']):
        try:
            if proc.info['name'] == PROCESS_NAME and proc.info['exe']:
                current_path = os.path.normpath(proc.info['exe']).lower()
                if current_path == target_path:
                    return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return False

def force_kill_specific_mt5():
    target_path = os.path.normpath(PATH_MT5).lower()
    killed = False
    for proc in psutil.process_iter(['pid', 'name', 'exe']):
        try:
            if proc.info['name'] == PROCESS_NAME and proc.info['exe']:
                current_path = os.path.normpath(proc.info['exe']).lower()
                if current_path == target_path:
                    proc.kill()
                    killed = True
        except:
            pass
    if killed:
        time.sleep(2)

def wait_for_connection(max_retries=10):
    for i in range(max_retries):
        info = mt5.terminal_info()
        if info and info.connected:
            return True
        time.sleep(1)
    return False

# --- VISIBILIDAD DE SÍMBOLOS ---
def ensure_all_symbols_visible():
    all_symbols = None
    for i in range(5):
        all_symbols = mt5.symbols_get(group="*")
        if all_symbols and len(all_symbols) > 10:
            break
        time.sleep(2)

    if not all_symbols:
        return

    count = 0
    for s in all_symbols:
        if not s.visible:
            if mt5.symbol_select(s.name, True):
                count += 1
    
    if count > 0:
        time.sleep(2) 

# --- ARRANQUE ---
def attempt_auth_start(account):
    return mt5.initialize(
        path=PATH_MT5,
        login=int(account['login']),
        password=account['password'],
        server=account['server'],
        timeout=5000,
        portable=False
    )

def ensure_mt5_is_ready(master_account):
    if is_specific_mt5_running():
        if attempt_auth_start(master_account):
            if wait_for_connection(max_retries=5):
                return True
    
    mt5.shutdown()
    force_kill_specific_mt5()
    
    if attempt_auth_start(master_account):
        if wait_for_connection(max_retries=10):
            return True
    return False

# --- EXTRACCIÓN DE DATOS ---
def get_deals_with_retry(from_date, to_date, retries=5):
    for i in range(retries):
        deals = mt5.history_deals_get(from_date, to_date, group="*")
        if deals is not None and len(deals) > 0:
            return deals
        time.sleep(1.5)
    return deals

def get_entry_info(position_id):
    history = mt5.history_deals_get(position=position_id)
    if history:
        for deal in history:
            if deal.entry == mt5.DEAL_ENTRY_IN:
                trade_type = "BUY" if deal.type == mt5.ORDER_TYPE_BUY else "SELL"
                return deal.time, trade_type
    return None, "UNKNOWN"

def get_account_financials(login_id):
    """
    Obtiene el balance actual y suma TODOS los retiros históricos.
    CORREGIDO: Ahora detecta Balance, Charges y Corrections.
    """
    account_info = mt5.account_info()
    if account_info is None:
        return {"balance": 0.0, "total_withdrawals": 0.0}
    
    current_balance = account_info.balance
    
    # Historial completo
    from_beginning = datetime(1990, 1, 1)
    to_now = datetime.now() + timedelta(days=1)
    
    history = mt5.history_deals_get(from_beginning, to_now, group="*")
    
    total_withdrawals = 0.0
    
    if history:
        for deal in history:
            # --- MODIFICACIÓN AQUÍ ---
            # Algunos brokers usan CHARGE (6) o CORRECTION (4) para retiros, no solo BALANCE (2)
            if deal.type in [mt5.DEAL_TYPE_BALANCE, mt5.DEAL_TYPE_CHARGE, mt5.DEAL_TYPE_CORRECTION]:
                
                # Si el profit es negativo, cuenta como retiro
                if deal.profit < 0:
                    total_withdrawals += deal.profit
                    
    return {
        "login": int(login_id),
        "balance": current_balance,
        "total_withdrawals": total_withdrawals
    }

def fetch_trades_for_account(login, password, server, last_sync_date_str):
    # Comprobamos si hay conexión IPC con el terminal
    if not mt5.terminal_info():
        logging.info(f"⚠️ MT5 no detectado. Intentando iniciar para cuenta {login}...")
        
        # Intentamos inicializar.
        if not mt5.initialize(path=PATH_MT5, login=int(login), password=password, server=server, portable=False):
            err_code, err_msg = mt5.last_error()
            return None, None, f"FATAL: No se pudo iniciar MT5. Error: {err_msg}"
        
        logging.info("✅ MT5 Iniciado correctamente.")
        time.sleep(2)

    # --- 1. INTENTO DE LOGIN ---
    # Si MT5 ya estaba abierto, hacemos switch de cuenta
    if not mt5.login(login=int(login), password=password, server=server):
        err_code, err_msg = mt5.last_error()
        full_error = f"Login Failed: {err_msg} (Verify credentials/server)"
        logging.error(f"❌ Error en cuenta {login}: {full_error}")
        return None, None, full_error

    # 2. VERIFICAR CONEXIÓN (Doble chequeo)
    if not wait_for_connection(max_retries=5):
        return None, None, "Timeout: Login ok, pero no hay conexión a internet/broker"
    
    ensure_all_symbols_visible()

    # 3. DATOS FINANCIEROS
    financials = get_account_financials(login)

    # 4. TRADES NUEVOS
    try:
        limit_date_dt = datetime.strptime(last_sync_date_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        limit_date_dt = datetime(2020, 1, 1)

    req_from = limit_date_dt - timedelta(days=2)
    req_to = datetime.now() + timedelta(days=1)
    
    deals = get_deals_with_retry(req_from, req_to)
    
    processed = []
    if deals:
        for d in deals:
            if d.entry in [mt5.DEAL_ENTRY_OUT, mt5.DEAL_ENTRY_INOUT]:
                deal_time = datetime.fromtimestamp(d.time)
                if deal_time <= limit_date_dt:
                    continue

                entry_ts, type_str = get_entry_info(d.position_id)
                
                date_str = deal_time.strftime('%Y-%m-%d')
                time_out_str = deal_time.strftime('%H:%M:%S')
                time_in_str = datetime.fromtimestamp(entry_ts).strftime('%H:%M:%S') if entry_ts else ""

                processed.append({
                    "ticket": d.ticket,
                    "position_id": d.position_id,
                    "trade_date": date_str,
                    "entry_time": time_in_str,
                    "exit_time": time_out_str,
                    "account": int(login),
                    "symbol": d.symbol,
                    "commission": d.commission,
                    "swap": d.swap,
                    "profit": d.profit,
                    "type": type_str,
                    "comment": d.comment
                })
    
    # Retorno exitoso (Error es None)
    return processed, financials, None

# --- ENDPOINT (ESTRUCTURA JSON ACTUALIZADA) ---
@app.route('/api/sync-trades', methods=['POST'])
@require_api_key
def sync_handler():
    req_data = request.json
    if not req_data or 'accounts' not in req_data:
        return jsonify({"status": "error", "message": "Payload inválido"}), 400

    #last_sync = req_data.get('last_sync_date', '2000-01-01 00:00:00')
    response_data_list = []

    try:
        for acc in req_data['accounts']:
            logging.info(f"🔄 Procesando: {acc['login']}")

            last_sync = acc.get('last_sync_date', '2000-01-01 00:00:00')
            
            # Desempaquetamos los 3 valores
            trades, finance_data, error_msg = fetch_trades_for_account(
                acc['login'], acc['password'], acc['server'], last_sync
            )
            
            # CASO A: ERROR DE CONEXIÓN / SERVIDOR INCORRECTO
            if error_msg:
                logging.warning(f"⚠️ Cuenta {acc['login']} falló: {error_msg}")
                response_data_list.append({
                    "account": acc['login'],
                    "status": "error",
                    "error_message": error_msg, # Aquí el cliente verá "Invalid Server", etc.
                    "balance": 0,
                    "new_trades": [],
                    "trades_count": 0
                })
                continue # Saltamos a la siguiente cuenta

            # CASO B: ÉXITO
            if finance_data:
                account_object = {
                    "account": finance_data['login'],
                    "status": "success", # Flag de éxito
                    "balance": finance_data['balance'],
                    "total_withdrawals": finance_data['total_withdrawals'],
                    "new_trades": trades,
                    "trades_count": len(trades)
                }
                response_data_list.append(account_object)
    
    except Exception as e:
        logging.error(f"🔥 Error NO Controlado: {e}")
        force_kill_specific_mt5() 
        return jsonify({"status": "fatal_error", "message": str(e)}), 500

    force_kill_specific_mt5()
    return jsonify({
        "status": "success", 
        "data": response_data_list
    })

# --- SYSTEM TRAY & FLASK ---
def create_icon_image():
    width = 64
    height = 64
    image = Image.new('RGB', (width, height), (0, 128, 255))
    dc = ImageDraw.Draw(image)
    dc.rectangle((width // 2, 0, width, height // 2), fill=(100, 255, 100))
    return image

def exit_action(icon, item):
    icon.stop()
    force_kill_specific_mt5()
    os._exit(0)

def run_flask_service():
    try:
        serve(app, host='0.0.0.0', port=PORT)
    except Exception as e:
        logging.error(f"Error Flask: {e}")

if __name__ == "__main__":
    force_kill_specific_mt5() 
    
    flask_thread = threading.Thread(target=run_flask_service)
    flask_thread.daemon = True
    flask_thread.start()
    
    icon = pystray.Icon("MT5_Service")
    icon.menu = pystray.Menu(
        item('Estado: Corriendo', lambda i, it: None, enabled=False),
        item(f'Puerto: {PORT}', lambda i, it: None, enabled=False),
        item('Salir', exit_action)
    )
    
    if getattr(sys, 'frozen', False):
        app_path = os.path.dirname(sys.executable)
    else:
        app_path = os.path.dirname(os.path.abspath(__file__))
    
    icon_path = os.path.join(app_path, 'icon.ico')
    
    if os.path.exists(icon_path):
        icon.icon = Image.open(icon_path)
    else:
        icon.icon = create_icon_image()
        
    icon.title = "MT5 API Connector"
    icon.run()