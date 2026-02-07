; --- CONFIGURACIÓN DEL INSTALADOR ---
#define MyAppName "MT5 API Connector"
#define MyAppVersion "1.0"
#define MyAppPublisher "Coding proactive"
#define MyAppExeName "MT5_API_Service.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-1234-567890ABCDEF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=.
OutputBaseFilename=Instalador_MT5_API
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Pedimos privilegios para escribir en Program Files
PrivilegesRequired=admin

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
; AQUÍ BUSCA TU .EXE CREADO CON PYINSTALLER
; Asegúrate de que la ruta 'Source' sea donde tienes tu .exe ahora mismo
Source: "C:\Users\Administrator\Documents\journal-history-installer\MT5_API_Service.exe"; DestDir: "{app}"; Flags: ignoreversion

; El archivo de icono físico, para que quede en la carpeta de instalación
Source: "C:\Users\Administrator\Documents\journal-history-installer\icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Code]
var
  PageMT5Path: TInputFileWizardPage;
  PagePort: TInputQueryWizardPage;
  GeneratedApiKey: String;

// Función para generar una API Key aleatoria (Alfanumérica 32 chars)
function GenerateRandomKey(Len: Integer): String;
var
  i: Integer;
  Chars: String;
begin
  Chars := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  Result := '';
  for i := 1 to Len do
    Result := Result + Chars[Random(Length(Chars)) + 1];
end;

// Inicialización del Asistente
procedure InitializeWizard;
begin
  // --- CORRECCIÓN 1: CreateInputFilePage (Sin "Wizard") ---
  PageMT5Path := CreateInputFilePage(
    wpSelectDir,
    'Configuración de MetaTrader 5',
    'Indique la ruta del ejecutable terminal64.exe',
    'El servicio necesita saber qué terminal controlar.'
  );
  
  // Agregamos el campo de selección de archivo
  PageMT5Path.Add(
    'Ruta completa de terminal64.exe:', 
    'Ejecutables (*.exe)|*.exe|Todos los archivos (*.*)|*.*', 
    '.exe'
  );
  
  // Valor por defecto
  PageMT5Path.Values[0] := 'C:\Program Files\MetaTrader 5\terminal64.exe';

  // --- CORRECCIÓN 2: CreateInputQueryPage (Sin "Wizard") ---
  PagePort := CreateInputQueryPage(
    PageMT5Path.ID,
    'Configuración de Red',
    'Defina el puerto de escucha para la API.',
    'IMPORTANTE: Debe abrir este puerto en el Firewall de Windows (Regla de Entrada TCP) manualmente.'
  );
  
  PagePort.Add('Puerto de escucha:', False);
  PagePort.Values[0] := '5000'; // Valor por defecto

  // Generamos la llave al iniciar
  GeneratedApiKey := GenerateRandomKey(32);
end;

// Función que se ejecuta al terminar la instalación
procedure CurStepChanged(CurStep: TSetupStep);
var
  JsonContent: String;
  ReadmeContent: String;
  ConfigPath: String;
  ReadmePath: String;
  MT5PathEscaped: String;
begin
  if CurStep = ssPostInstall then
  begin
    ConfigPath := ExpandConstant('{app}\config.json');
    ReadmePath := ExpandConstant('{app}\LEER_IMPORTANTE.txt');
    
    // Escapar backslashes para JSON (C:\Path -> C:\\Path)
    MT5PathEscaped := PageMT5Path.Values[0];
    StringChange(MT5PathEscaped, '\', '\\');

    // 1. CREAR CONFIG.JSON
    JsonContent := '{' + #13#10 +
      '  "mt5_path": "' + MT5PathEscaped + '",' + #13#10 +
      '  "port": ' + PagePort.Values[0] + ',' + #13#10 +
      '  "api_key": "' + GeneratedApiKey + '"' + #13#10 +
      '}';
    
    SaveStringToFile(ConfigPath, JsonContent, False);

    // 2. CREAR README CON INSTRUCCIONES
    ReadmeContent := '=== MT5 API SERVICE - INSTALACIÓN COMPLETADA ===' + #13#10 + #13#10 +
      'IMPORTANTE: Este servicio se ejecuta en segundo plano.' + #13#10 +
      'Para detenerlo, use el Administrador de Tareas.' + #13#10 + #13#10 +
      '--- SUS CREDENCIALES ---' + #13#10 +
      'API KEY GENERADA: ' + GeneratedApiKey + #13#10 + #13#10 +
      '--- EJEMPLO DE CONSUMO ---' + #13#10 +
      'Método: POST' + #13#10 +
      'URL: http://localhost:' + PagePort.Values[0] + '/api/sync-trades' + #13#10 +
      'Headers:' + #13#10 +
      '    Content-Type: application/json' + #13#10 +
      '    X-API-KEY: ' + GeneratedApiKey + #13#10 + #13#10 +
      'Payload:' + #13#10 +
      '{' + #13#10 +
      '    "accounts": [{"login": 123, "password": "...", "server": "..."}],' + #13#10 +
      '    "last_sync_date": "2023-01-01 00:00:00"' + #13#10 +
      '}';

    SaveStringToFile(ReadmePath, ReadmeContent, False);
  end;
end;

[Run]
; Al finalizar, abrir el archivo LEER_IMPORTANTE.txt automáticamente
Filename: "{app}\LEER_IMPORTANTE.txt"; Description: "Ver API Key e instrucciones"; Flags: postinstall shellexec waituntilterminated
; Opción para arrancar el servicio de una vez
Filename: "{app}\{#MyAppExeName}"; Description: "Iniciar el servicio ahora"; Flags: postinstall nowait