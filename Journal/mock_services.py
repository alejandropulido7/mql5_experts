from flask import Flask, jsonify, request
import logging

# Configuración básica de logs para ver qué llega
logging.basicConfig(level=logging.INFO, format='%(asctime)s - SERVER - %(message)s')

app = Flask(__name__)

# --- BASE DE DATOS SIMULADA ---
# COLOCA AQUÍ CREDENCIALES REALES para que tu script de MT5 pueda loguearse
MOCK_ACCOUNTS = [
    {
        "id": 1,
        "login": 9117125,
        "password": "seiymY2=",
        "server": "SureLeverageFunding-MT5"
    },
    {
        "id": 2,
        "login": 9116741,        # Tu login real de MT5
        "password": "svbigV2/", # Tu password real
        "server": "SureLeverageFunding-MT5" # Tu servidor real
    }
    
]

# Almacenamiento en memoria de los trades recibidos
RECEIVED_TRADES_DB = []

# --- ENDPOINTS ---

@app.route('/api/accounts', methods=['GET'])
def get_accounts():
    """
    Simula la llamada a NocoDB para obtener la lista de cuentas a auditar.
    """
    logging.info("Solicitud recibida: Entregando lista de cuentas.")
    # Mantenemos la estructura {'list': [...]} que usabas en el ejemplo anterior
    return jsonify({"list": MOCK_ACCOUNTS}), 200

@app.route('/api/ingest', methods=['POST'])
def ingest_trades():
    """
    Simula el endpoint que recibe y guarda los trades en la base de datos.
    """
    payload = request.json
    
    if not payload:
        return jsonify({"error": "Payload vacío"}), 400

    count = len(payload)
    logging.info(f"Recibido lote de {count} trades.")
    
    # Guardar en memoria (Simulación de INSERT en SQL)
    RECEIVED_TRADES_DB.extend(payload)
    
    # Imprimir el primer trade para verificar estructura
    if count > 0:
        logging.info(f"Ejemplo de data recibida: {payload}")

    return jsonify({"status": "success", "inserted": count}), 201

@app.route('/api/debug/db', methods=['GET'])
def view_db():
    """
    Endpoint extra para que puedas ver en el navegador qué se ha guardado hasta ahora.
    """
    return jsonify(RECEIVED_TRADES_DB), 200

if __name__ == '__main__':
    logging.info("Iniciando Servidor Mock en http://127.0.0.1:5000")
    app.run(debug=True, port=5000)