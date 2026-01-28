import MetaTrader5 as mt5
import time
import requests
import logging
import os
import psutil  # Necesitarás instalar esto: pip install psutil
from datetime import datetime, timedelta

# --- CONFIGURACIÓN ---
BASE_URL = "http://127.0.0.1:5000" 
CREDS_ENDPOINT = f"{BASE_URL}/api/accounts"
INGEST_ENDPOINT = f"{BASE_URL}/api/ingest"
API_TOKEN = "dev_token_123"

# Ruta exacta de tu terminal
PATH_MT5 = r"C:\Program Files\RoboForex MT5 Terminal\terminal64.exe"
# Nombre del proceso para buscarlo y matarlo (usualmente terminal64.exe)
PROCESS_NAME = "terminal64.exe"

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def force_kill_mt5():
    """
    Estrategia de limpieza: Busca y termina cualquier proceso de MT5 corriendo
    para liberar RAM y sockets en la VPS.
    """
    logging.info("Iniciando limpieza profunda de procesos MT5...")
    killed_count = 0
    for proc in psutil.process_iter(['pid', 'name', 'exe']):
        try:
            # Verificamos si es terminal64.exe y si coincide con nuestra ruta (opcional)
            if proc.info['name'] == PROCESS_NAME:
                proc.kill()
                killed_count += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
    
    if killed_count > 0:
        logging.info(f"Se eliminaron {killed_count} instancias de MT5 de la memoria.")
    else:
        logging.info("El sistema ya estaba limpio.")

def get_accounts():
    try:
        response = requests.get(CREDS_ENDPOINT)
        response.raise_for_status()
        return response.json()['list']
    except Exception as e:
        logging.error(f"Error obteniendo credenciales: {e}")
        return []

def get_entry_info(position_id):
    history = mt5.history_deals_get(position=position_id)
    if history:
        for deal in history:
            if deal.entry == mt5.DEAL_ENTRY_IN:
                trade_type = "BUY" if deal.type == mt5.ORDER_TYPE_BUY else "SELL"
                return deal.time, trade_type
    return None, "UNKNOWN"

def sync_account(account_data):
    login_id = int(account_data['login'])
    password = account_data['password']
    server = account_data['server']

    # Login
    if not mt5.login(login=login_id, password=password, server=server):
        logging.error(f"Fallo login en {login_id}: {mt5.last_error()}")
        return [] 

    # Rango de tiempo (Hoy)
    to_date = datetime.now()
    from_date = datetime(to_date.year, to_date.month, to_date.day)
    ayer = to_date - timedelta(days=1)

    logging.info(f"Fecha ayer: {ayer} - Fecha hoy: {to_date}")

    deals = mt5.history_deals_get(ayer, to_date)

    ##logging.info(f"Deals: {len(deals)}")
    
    if deals is None:
        return []

    processed_trades = []
    
    for d in deals:
        if d.entry == mt5.DEAL_ENTRY_OUT or d.entry == mt5.DEAL_ENTRY_INOUT:
            entry_time_ts, trade_type = get_entry_info(d.position_id)
            
            # Cálculo de fechas
            fecha_trade_str = datetime.fromtimestamp(d.time).strftime('%Y-%m-%d')
            logging.info(f"Fecha trade: {from_date}")
            hora_salida_str = datetime.fromtimestamp(d.time).strftime('%H:%M:%S')
            hora_entrada_str = ""
            if entry_time_ts:
                hora_entrada_str = datetime.fromtimestamp(entry_time_ts).strftime('%H:%M:%S')

            trade_data = {
                "Ticket": d.ticket,
                "position_id": d.position_id,
                "Fecha trade": fecha_trade_str,
                "Hora entrada": hora_entrada_str,
                "Hora salida": hora_salida_str,
                "Cuenta": login_id,
                "Activo": d.symbol,
                "Comision": d.commission,
                "Swap": d.swap,
                "Profit": d.profit,
                "Tipo": trade_type,
                "Comment": d.comment
            }
            processed_trades.append(trade_data)

    logging.info(f"Cuenta: {login_id} - trades: {len(processed_trades)}")
    return processed_trades

def run_orchestrator():
    # 1. LIMPIEZA PREVENTIVA (Kill process)
    force_kill_mt5()
    time.sleep(2)

    # 2. OBTENER CUENTAS (Antes de abrir MT5)
    # Necesitamos las credenciales para poder abrir el terminal en modo "Silencioso"
    accounts = get_accounts()
    
    if not accounts:
        logging.warning("No se obtuvieron cuentas de la API. Abortando ciclo.")
        return

    # Usamos la PRIMERA cuenta de la lista para el arranque inicial
    # Esto evita el pop-up de "Ingrese contraseña"
    master_acc = accounts[0]
    
    logging.info(f"Iniciando MT5 con cuenta maestra: {master_acc['login']}...")

    # --- CAMBIO CLAVE AQUÍ ---
    # Pasamos login, password y server DENTRO de initialize
    if not mt5.initialize(
        path=PATH_MT5, 
        login=int(master_acc['login']), 
        password=master_acc['password'], 
        server=master_acc['server'],
        timeout=10000  # Damos 10 segundos para conectar
    ):
        logging.error(f"Error crítico: No se pudo iniciar MT5: {mt5.last_error()}")
        # Si falla, intentamos forzar el cierre para no dejar procesos zombies
        force_kill_mt5()
        return
    # -------------------------

    logging.info("MT5 Inicializado correctamente. Comenzando iteración...")
    
    MASTER_PAYLOAD = [] 

    for acc in accounts:
        # Nota: Aunque ya estamos logueados en la primera cuenta (master_acc),
        # el ciclo 'sync_account' volverá a hacer login. 
        # MT5 maneja esto bien: si es la misma cuenta, no hace nada; si es otra, cambia.
        
        logging.info(f"Procesando cuenta: {acc['login']}...")
        account_trades = sync_account(acc)
        
        if account_trades:
            MASTER_PAYLOAD.extend(account_trades)
            logging.info(f" -> {len(account_trades)} trades encontrados.")
        
        time.sleep(1)

    # 3. ENVÍO DE DATOS
    if MASTER_PAYLOAD:
        logging.info(f"Enviando total de {len(MASTER_PAYLOAD)} trades al servidor...")
        try:
            res = requests.post(INGEST_ENDPOINT, json=MASTER_PAYLOAD)
            if res.status_code in [200, 201]:
                logging.info("ÉXITO: Datos sincronizados correctamente.")
            else:
                logging.error(f"Error del servidor: {res.text}")
        except Exception as e:
            logging.error(f"Error de conexión API: {e}")
    else:
        logging.info("No hubo trades cerrados hoy en ninguna cuenta.")

    # 4. LIMPIEZA FINAL
    mt5.shutdown()
    ##force_kill_mt5()

if __name__ == "__main__":
    # Necesario instalar psutil: pip install psutil
    while True:
        print("\n--- Iniciando Ciclo ---")
        run_orchestrator()
        print("--- Ciclo terminado. Esperando 60 segundos ---")
        time.sleep(60)