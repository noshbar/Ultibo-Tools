unit Updater;

{$mode objfpc}{$H+}

interface

uses
  GlobalConst;

const Updater_FinalName = 'c:\kernel7.img';
const Updater_TempName  = 'c:\kernel7.tmp';
const Updater_Pin       = GPIO_PIN_18;
const Updater_Location  = 'http://192.168.0.1:8080/kernel7.img';

function UpdateKernel(AutoReboot : Boolean) : Boolean;

implementation

uses
  GlobalConfig,
  GlobalTypes,
  Platform,
  SysUtils,
  Keyboard,
  Classes,
  Console,
  Ultibo,
  FileSystem,
  FATFS,
  MMC,
  HTTP,
  GPIO;

type
  TCleanupData = record
    FileStream : TFSFileStream;
    HTTPClient : THTTPClient;
    WindowHandle : TWindowHandle;
  end;

procedure CleanupData(Data : TCleanupData);
begin
  Data.FileStream.Free;
  Data.HTTPClient.Free;
  if (Data.WindowHandle <> 0) then
    ConsoleWindowDestroy(Data.WindowHandle);
end;

function UpdateKernel(AutoReboot : Boolean) : Boolean;
var
  existingDate, newDate : integer;
  count : integer;
  keypress : Word;

  data : TCleanupData;
begin
  Result := False;

  // only update if the configured pin is connected to ground
  GPIOPullSelect(Updater_Pin, GPIO_PULL_UP);
  GPIOFunctionSelect(Updater_Pin, GPIO_FUNCTION_IN);
  if (GPIOInputGet(Updater_Pin) = GPIO_LEVEL_HIGH) then
    exit;

  data.FileStream := nil;
  data.HTTPClient := nil;
  data.WindowHandle := ConsoleWindowCreate(ConsoleDeviceGetDefault, CONSOLE_POSITION_FULLSCREEN, True);

  write('Waiting for SD card');
  while not DirectoryExists('C:\') do
  begin
    write('.');
    Sleep(100);
  end;
  writeln;

  try
    if FSFileExists(Updater_FinalName) then // in theory this shouldn't be possible, because how could we be running with a kernel... unless we're in QEMU...
    begin
      writeln('Getting existing file date information...');
      data.FileStream := TFSFileStream.Create(Updater_FinalName, fmOpenRead);
      existingDate := FSFileGetDate(data.FileStream.Handle);
      data.FileStream.Destroy;
    end;
  except on e: Exception do
    begin
      writeln('Exception: ', e.Message);
      CleanupData(data);
      exit;
    end;
  end;

  writeln('Checking existing temporary file...');
  {Check Temp File}
  if FSFileExists(Updater_TempName) then
  begin
    writeln('Deleting existing temporary file ' + Updater_TempName);
    {Temp Backup File}
    FSFileSetAttr(Updater_TempName, faNone);
    if not FSDeleteFile(Updater_TempName) then
    begin
      writeln('Could not delete existing temporary file');
      CleanupData(data);
      exit;
    end;
  end;

  count := 0;
  write('Waiting for network (press ESCAPE to abort)');
  data.HTTPClient := THTTPClient.Create;
  while (data.HTTPClient.LocalAddress = '') OR (data.HTTPClient.LocalAddress = '0.0.0.0') OR (data.HTTPClient.LocalAddress = '255.255.255.255') do
  begin
    write('.');
    data.HTTPClient.Destroy;
    Sleep(100);
    count := count + 1;
    // check for ESCAPE to break out the wait
    if (count >= 200) OR ((KeyboardPeek <> ERROR_NO_MORE_ITEMS) AND (KeyboardGet(keypress) = ERROR_SUCCESS) AND (keypress = KEY_CODE_ESCAPE)) then
    begin
      writeln;
      writeln('No network found, exiting...');
      CleanupData(data);
      exit;
    end;
    data.HTTPClient := THTTPClient.Create;
  end;
  writeln;

  data.HTTPClient.ReceiveSize := SIZE_4M;
  writeln('Opening new file...');
  data.FileStream := TFSFileStream.Create(Updater_TempName, fmCreate);
  writeln('Attempting HTTP stream...');
  try
    if not data.HTTPClient.GetStream(Updater_Location, data.FileStream) then
    begin
      writeln('HTTP GET request failed (Status=' + HTTPStatusToString(data.HTTPClient.ResponseStatus) + ' Reason=' + data.HTTPClient.ResponseReason + ')');
      CleanupData(data);
      exit;
    end;
  except on e: Exception do
    begin
      writeln('Exception thrown: ', e.Message);
      CleanupData(data);
      exit;
    end;
  end;

  writeln('Stream received...');
  try
    {Check Status}
    case data.HTTPClient.ResponseStatus of
      HTTP_STATUS_OK:
      begin
        {Set Date/Time}
        newDate := FileTimeToFileDate(RoundFileTime(HTTPDateToFileTime(data.HTTPClient.GetResponseHeader(HTTP_ENTITY_HEADER_LAST_MODIFIED))));
        FSFileSetDate(data.FileStream.Handle, newDate);
        if (newDate = existingDate) then
        begin
          writeln('No update necessary');
          CleanupData(data);
          exit;
        end;
      end;
      HTTP_STATUS_NOT_FOUND:
      begin
        writeln('No update found');
        CleanupData(data);
        exit;
      end;
    else
      writeln('HTTP GET request not successful (Status=' + HTTPStatusToString(data.HTTPClient.ResponseStatus) + ' Reason=' + data.HTTPClient.ResponseReason + ')');
      CleanupData(data);
      exit;
    end;
  except on e: Exception do
    begin
      writeln('Exception thrown: ', e.Message);
      CleanupData(data);
      exit;
    end;
  end;

  writeln('Closing file...');
  data.FileStream.Destroy;

  try
    writeln('Renaming file...');
    FSFileSetAttr(Updater_FinalName, faNone);
    FSDeleteFile(Updater_FinalName);
    if not FSRenameFile(Updater_TempName, Updater_FinalName) then
    begin
      CleanupData(data);
      exit;
    end;
  except on e: Exception do
    begin
      writeln('Exception thrown: ', e.Message);
      CleanupData(data);
      exit;
    end;
  end;

  if (AutoReboot) then
    SystemRestart(0);

  CleanupData(data);
  Result := True;
end;

end.

