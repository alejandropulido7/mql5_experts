import MetaTrader5 as mt5
import logging
from flask import Flask, request, jsonify
from datetime import datetime, timedelta
import pandas as pd
import psutil
import time
from waitress import serve

# --- CONFIGURACIÓN ---
PATH_MT5 = r"C:\Program Files\MT5-history\terminal64.exe"
PROCESS_NAME = "terminal64.exe"

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - API - %(message)s')

# --- UTILIDADES DE SISTEMA ---
def force_kill_mt5():
    """Mata el proceso forzosamente para limpiar estados corruptos."""
    logging.warning("⚠️ KILL SWITCH: Matando procesos de MT5...")
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            if proc.info['name'] == PROCESS_NAME:
                proc.kill()
        except:
            pass
    time.sleep(2) # Tiempo para liberar el archivo .exe

def wait_for_connection(max_retries=10):
    """Verifica conexión real a internet/broker."""
    for i in range(max_retries):
        info = mt5.terminal_info()
        if info and info.connected:
            return True
        time.sleep(1)
    return False

# --- LÓGICA DE VISIBILIDAD DE SÍMBOLOS ---
def ensure_all_symbols_visible():
    """Fuerza la descarga y activación de todos los símbolos del broker."""
    all_symbols = None
    for i in range(5):
        all_symbols = mt5.symbols_get(group="*")
        if all_symbols and len(all_symbols) > 10:
            break
        time.sleep(2)

    if not all_symbols:
        logging.warning("⚠️ No se pudo obtener la lista completa de símbolos.")
        return

    count = 0
    for s in all_symbols:
        if not s.visible:
            if mt5.symbol_select(s.name, True):
                count += 1
    
    if count > 0:
        logging.info(f"✅ Se activaron {count} símbolos nuevos. Sincronizando...")
        time.sleep(2) 

# --- LÓGICA DE ARRANQUE ROBUSTA (MODIFICADA) ---
def attempt_auth_start(account):
    """
    Intenta iniciar/conectar MT5 pasando SIEMPRE credenciales.
    Esto sobrescribe cualquier sesión anterior y evita pop-ups.
    """
    logging.info(f"🔑 Intentando inicializar con credenciales de cuenta {account['login']}...")
    
    return mt5.initialize(
        path=PATH_MT5,
        login=int(account['login']),
        password=account['password'],
        server=account['server'],
        timeout=20000,
        portable=False
    )

def ensure_mt5_is_ready(master_account):
    """
    Orquestador de Salud del Terminal:
    1. Intenta conectar con credenciales (incluso si ya está abierto).
    2. Si falla, MATA el proceso y reintenta desde cero (Hard Reset).
    """
    
    # INTENTO 1: Hot-Swap (Si ya está abierto, intenta loguearse encima)
    if attempt_auth_start(master_account):
        if wait_for_connection(max_retries=5):
            logging.info("✅ MT5 Conectado (Hot Start).")
            return True
        else:
            logging.warning("⚠️ MT5 arrancó pero no conecta. Probando reinicio forzado...")
    
    # Si llegamos aquí, el intento suave falló o no hay conexión.
    # INTENTO 2: Cold-Start (Matar y arrancar de nuevo)
    mt5.shutdown()
    force_kill_mt5()
    
    if attempt_auth_start(master_account):
        if wait_for_connection(max_retries=10):
            logging.info("✅ MT5 Conectado tras reinicio (Cold Start).")
            return True
    
    logging.error("❌ MT5 no responde incluso tras reinicio forzado.")
    return False

# --- EXTRACCIÓN DE DATOS ---
def get_deals_with_retry(from_date, to_date, retries=5):
    """Reintenta si MT5 devuelve 0 deals por lentitud de disco."""
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

def fetch_trades_for_account(login, password, server, last_sync_date_str):
    # 1. Login Explícito (Cambio de cuenta)
    if not mt5.login(login=int(login), password=password, server=server):
        logging.error(f"Fallo login {login}: {mt5.last_error()}")
        return []

    if not wait_for_connection(max_retries=10):
        return []
    
    ensure_all_symbols_visible()

    # 2. Definir Fechas
    try:
        limit_date_dt = datetime.strptime(last_sync_date_str, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        limit_date_dt = datetime(2020, 1, 1)

    req_from = datetime.now() - timedelta(days=30)
    req_to = datetime.now() + timedelta(days=1)
    
    # 3. Obtener Deals
    deals = get_deals_with_retry(limit_date_dt, req_to)
    
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
                    "Ticket": d.ticket,
                    "position_id": d.position_id,
                    "Fecha trade": date_str,
                    "Hora entrada": time_in_str,
                    "Hora salida": time_out_str,
                    "Cuenta": int(login),
                    "Activo": d.symbol,
                    "Comision": d.commission,
                    "Swap": d.swap,
                    "Profit": d.profit,
                    "Tipo": type_str,
                    "Comment": d.comment
                })
    
    return processed

# --- ENDPOINT API ---
@app.route('/api/sync-trades', methods=['POST'])
def sync_handler():
    req_data = request.json
    if not req_data or 'accounts' not in req_data:
        return jsonify({"status": "error", "message": "Payload inválido"}), 400

    last_sync = req_data.get('last_sync_date', '2000-01-01 00:00:00')
    all_results = []

    # --- CAMBIO CRÍTICO AQUI ---
    # Pasamos la cuenta maestra para que SIEMPRE se use en el arranque
    master_acc = req_data['accounts'][0]
    
    if not ensure_mt5_is_ready(master_acc):
        # Si falló todo, intentamos una última limpieza desesperada para la próxima
        force_kill_mt5()
        return jsonify({"status": "error", "message": "MT5 Failure: No se pudo arrancar ni recuperar."}), 500

    try:
        for acc in req_data['accounts']:
            logging.info(f"🔄 Procesando cuenta: {acc['login']}")
            trades = fetch_trades_for_account(
                acc['login'], acc['password'], acc['server'], last_sync
            )
            if trades:
                all_results.extend(trades)
                logging.info(f" -> {len(trades)} nuevos trades.")
    
    except Exception as e:
        logging.error(f"🔥 Error Fatal: {e}")
        force_kill_mt5() 
        return jsonify({"status": "error", "message": str(e)}), 500

    return jsonify({
        "status": "success", 
        "count": len(all_results), 
        "data": all_results
    })

if __name__ == "__main__":
    print("--- SERVIDOR MT5 API LISTO (Modo Estricto) ---")
    force_kill_mt5() # Limpieza al iniciar el servicio
    serve(app, host='0.0.0.0', port=5000)