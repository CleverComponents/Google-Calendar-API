{
  Copyright (C) 2015 by Clever Components

  Author: Sergey Shirokov <admin@clevercomponents.com>

  Website: www.CleverComponents.com

  This file is part of Google API Client Library for Delphi.

  Google API Client Library for Delphi is free software:
  you can redistribute it and/or modify it under the terms of
  the GNU Lesser General Public License version 3
  as published by the Free Software Foundation and appearing in the
  included file COPYING.LESSER.

  Google API Client Library for Delphi is distributed in the hope
  that it will be useful, but WITHOUT ANY WARRANTY; without even the
  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the GNU Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with Json Serializer. If not, see <http://www.gnu.org/licenses/>.

  The current version of Google API Client Library for Delphi needs for
  the non-free library Clever Internet Suite. This is a drawback,
  and we suggest the task of changing
  the program so that it does the same job without the non-free library.
  Anyone who thinks of doing substantial further work on the program,
  first may free it from dependence on the non-free library.
}

unit GoogleApis.Persister;

interface

uses
  System.Classes, System.SysUtils, GoogleApis, clOAuth, clHttp, clUriUtils, clHttpRequest, clJsonSerializer;

type
  TGoogleOAuthCredential = class(TCredential)
  strict private
    FScope: string;
    FClientID: string;
    FClientSecret: string;
    FOAuth: TclOAuth;
  public
    constructor Create;
    destructor Destroy; override;

    function GetAuthorization: string; override;
    function RefreshAuthorization: string; override;
    procedure RevokeAuthorization; override;
    procedure Abort; override;

    property ClientID: string read FClientID write FClientID;
    property ClientSecret: string read FClientSecret write FClientSecret;
    property Scope: string read FScope write FScope;
  end;

  TGoogleApisHttpClient = class(THttpClient)
  strict private
    FHttp: TclHttp;

    function CreateRequest(AParameters: THttpRequestParameterList): TclHttpRequest;
    function GetRequestUri(const AUri: string; AParameters: THttpRequestParameterList): string;
    procedure CheckResponse(const AJsonResponse: string);
  strict protected
    function GetStatusCode: Integer; override;
  public
    constructor Create(AInitializer: TServiceInitializer);
    destructor Destroy; override;

    function Get(const AUri: string; AParameters: THttpRequestParameterList): string; override;
    function Post(const AUri: string; AParameters: THttpRequestParameterList; const AJsonRequest: string): string; override;
    function Put(const AUri: string; AParameters: THttpRequestParameterList; const AJsonRequest: string): string; override;
    function Patch(const AUri: string; AParameters: THttpRequestParameterList; AJsonRequest: string): string; override;
    function Delete(const AUri: string): string; override;
    procedure Abort; override;
  end;

  TGoogleApisJsonSerializer = class(TJsonSerializer)
  strict private
    FSerializer: clJsonSerializer.TclJsonSerializer;
  public
    constructor Create;
    destructor Destroy; override;

    function JsonToException(const AJson: string): EGoogleApisException; override;
    function ExceptionToJson(E: EGoogleApisException): string; override;

    function JsonToObject(AType: TClass; const AJson: string): TObject; override;
    function ObjectToJson(AObject: TObject): string; override;
  end;

  TGoogleApisServiceInitializer = class(TServiceInitializer)
  strict private
    FHttpClient: THttpClient;
    FJsonSerializer: TJsonSerializer;
  strict protected
    function GetHttpClient: THttpClient; override;
    function GetJsonSerializer: TJsonSerializer; override;
  public
    constructor Create(ACredential: TCredential; const ApplicationName: string);
    destructor Destroy; override;
  end;

implementation

{$I clVer.inc}

{ TGoogleOAuthCredential }

procedure TGoogleOAuthCredential.Abort;
begin
  FOAuth.Close();
end;

constructor TGoogleOAuthCredential.Create;
begin
  inherited Create();
  FOAuth := TclOAuth.Create(nil);
end;

destructor TGoogleOAuthCredential.Destroy;
begin
  FOAuth.Free();
  inherited Destroy();
end;

function TGoogleOAuthCredential.GetAuthorization: string;
begin
  FOAuth.AuthURL := 'https://accounts.google.com/o/oauth2/auth';
  FOAuth.TokenURL := 'https://accounts.google.com/o/oauth2/token';
  FOAuth.RedirectURL := 'http://localhost';
  FOAuth.ClientID := ClientID;
  FOAuth.ClientSecret := ClientSecret;
  FOAuth.Scope := Scope;

  Result := FOAuth.GetAuthorization();
end;

function TGoogleOAuthCredential.RefreshAuthorization: string;
begin
  Result := FOAuth.RefreshAuthorization();
end;

procedure TGoogleOAuthCredential.RevokeAuthorization;
begin
  FOAuth.Close();
end;

{ TGoogleApisHttpClient }

procedure TGoogleApisHttpClient.Abort;
begin
  FHttp.Close();
end;

procedure TGoogleApisHttpClient.CheckResponse(const AJsonResponse: string);
begin
  if (FHttp.StatusCode >= 300) then
  begin
    if (FHttp.ResponseHeader.ContentType.ToLower().IndexOf('json') > -1) then
    begin
      raise Initializer.JsonSerializer.JsonToException(AJsonResponse);
    end else
    begin
      raise EclHttpError.Create(FHttp.StatusText, FHttp.StatusCode, AJsonResponse);
    end;
  end;
end;

constructor TGoogleApisHttpClient.Create(AInitializer: TServiceInitializer);
begin
  inherited Create(AInitializer);

  FHttp := TclHttp.Create(nil);
  FHttp.UserAgent := Initializer.ApplicationName;
  FHttp.SilentHTTP := True;
  //TODO test it FHttp.Expect100Continue := True;
end;

function TGoogleApisHttpClient.CreateRequest(AParameters: THttpRequestParameterList): TclHttpRequest;
var
  i: Integer;
begin
  Result := TclHttpRequest.Create(nil);
  try
    Result.Header.CharSet := 'UTF-8';
    for i := 0 to AParameters.Count - 1 do
    begin
      Result.AddFormField(AParameters[i].Name, AParameters[i].Value);
    end;
  except
    Result.Free();
    raise;
  end;
end;

function TGoogleApisHttpClient.Delete(const AUri: string): string;
var
  resp: TStringStream;
begin
  resp := TStringStream.Create('', TEncoding.UTF8, False);
  try
    FHttp.Authorization := Initializer.Credential.GetAuthorization();

    FHttp.Delete(AUri, resp);

    CheckResponse(resp.DataString);

    Result := resp.DataString;
  finally
    resp.Free();
  end;
end;

destructor TGoogleApisHttpClient.Destroy;
begin
  FHttp.Free();
  inherited Destroy();
end;

function TGoogleApisHttpClient.Get(const AUri: string; AParameters: THttpRequestParameterList): string;
var
  resp: TStringStream;
begin
  resp := TStringStream.Create('', TEncoding.UTF8, False);
  try
    FHttp.Authorization := Initializer.Credential.GetAuthorization();

    FHttp.Get(GetRequestUri(AUri, AParameters), resp);

    CheckResponse(resp.DataString);

    Result := resp.DataString;
  finally
    resp.Free();
  end;
end;

function TGoogleApisHttpClient.GetRequestUri(const AUri: string; AParameters: THttpRequestParameterList): string;
var
  req: TclHttpRequest;
begin
  req := CreateRequest(AParameters);
  try
    Result := Trim(req.RequestSource.Text);
    if (Result <> '') then
    begin
      Result := '?' + Result;
    end;

{$IFDEF CLVERSION94}
    Result := TclUrlEncoder.Encode(AUri, 'UTF-8') + Result;
{$ELSE}
    Result := TclUrlParser.EncodeUrl(AUri, 'UTF-8') + Result;
{$ENDIF}

  finally
    req.Free();
  end;
end;

function TGoogleApisHttpClient.GetStatusCode: Integer;
begin
  Result := FHttp.StatusCode;
end;

function TGoogleApisHttpClient.Patch(const AUri: string; AParameters: THttpRequestParameterList; AJsonRequest: string): string;
var
  req: TclHttpRequest;
  resp: TStringStream;
begin
  req := nil;
  resp := nil;
  try
    req := TclHttpRequest.Create(nil);
    req.BuildJSONRequest(AJsonRequest);

    resp := TStringStream.Create('', TEncoding.UTF8, False);

    FHttp.Authorization := Initializer.Credential.GetAuthorization();

    FHttp.SendRequest('PATCH', GetRequestUri(AUri, AParameters), req, resp);

    CheckResponse(resp.DataString);

    Result := resp.DataString;
  finally
    resp.Free();
    req.Free();
  end;
end;

function TGoogleApisHttpClient.Post(const AUri: string; AParameters: THttpRequestParameterList; const AJsonRequest: string): string;
var
  req: TclHttpRequest;
  resp: TStringStream;
begin
  req := nil;
  resp := nil;
  try
    req := TclHttpRequest.Create(nil);

    if (AJsonRequest <> '') then
    begin
      req.BuildJSONRequest(AJsonRequest);
    end;

    resp := TStringStream.Create('', TEncoding.UTF8, False);

    FHttp.Authorization := Initializer.Credential.GetAuthorization();

    FHttp.Post(GetRequestUri(AUri, AParameters), req, resp);

    CheckResponse(resp.DataString);

    Result := resp.DataString;
  finally
    resp.Free();
    req.Free();
  end;
end;

function TGoogleApisHttpClient.Put(const AUri: string; AParameters: THttpRequestParameterList; const AJsonRequest: string): string;
var
  req, resp: TStringStream;
begin
  req := nil;
  resp := nil;
  try
    req := TStringStream.Create(AJsonRequest, TEncoding.UTF8, False);
    resp := TStringStream.Create('', TEncoding.UTF8, False);

    FHttp.Authorization := Initializer.Credential.GetAuthorization();

    FHttp.Put(GetRequestUri(AUri, AParameters), 'application/json', req, resp);

    CheckResponse(resp.DataString);

    Result := resp.DataString;
  finally
    resp.Free();
    req.Free();
  end;
end;

{ TGoogleApisServiceInitializer }

constructor TGoogleApisServiceInitializer.Create(ACredential: TCredential; const ApplicationName: string);
begin
  inherited Create(ACredential, ApplicationName);

  FHttpClient := nil;
  FJsonSerializer := nil;
end;

destructor TGoogleApisServiceInitializer.Destroy;
begin
  FHttpClient.Free();
  FJsonSerializer.Free();

  inherited Destroy();
end;

function TGoogleApisServiceInitializer.GetHttpClient: THttpClient;
begin
  if (FHttpClient = nil) then
  begin
    FHttpClient := TGoogleApisHttpClient.Create(Self);
  end;
  Result := FHttpClient;
end;

function TGoogleApisServiceInitializer.GetJsonSerializer: TJsonSerializer;
begin
  if (FJsonSerializer = nil) then
  begin
    FJsonSerializer := TGoogleApisJsonSerializer.Create();
  end;
  Result := FJsonSerializer;
end;

{ TGoogleApisJsonSerializer }

constructor TGoogleApisJsonSerializer.Create;
begin
  inherited Create();
  FSerializer := clJsonSerializer.TclJsonSerializer.Create();
end;

destructor TGoogleApisJsonSerializer.Destroy;
begin
  FSerializer.Free();
  inherited Destroy();
end;

function TGoogleApisJsonSerializer.ExceptionToJson(E: EGoogleApisException): string;
begin
  Result := FSerializer.ObjectToJson(E);
end;

function TGoogleApisJsonSerializer.JsonToException(const AJson: string): EGoogleApisException;
begin
  Result := EGoogleApisException.Create();
  try
    Result := FSerializer.JsonToObject(Result, AJson) as EGoogleApisException;
  except
    Result.Free();
    raise;
  end;
end;

function TGoogleApisJsonSerializer.JsonToObject(AType: TClass; const AJson: string): TObject;
begin
  Result := FSerializer.JsonToObject(AType, AJson);
end;

function TGoogleApisJsonSerializer.ObjectToJson(AObject: TObject): string;
begin
  Result := FSerializer.ObjectToJson(AObject);
end;

end.
