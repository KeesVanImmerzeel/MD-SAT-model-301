library dsmodel301;
  {-Model voor het combineren van de berekeningsresultaten van maximaal 5 mo-
    dellen. De 6-de invoerset (RP6) bevat de 'sleutel-waarde' (=key). Deze
    waarde bepaalt van welk model (1-5) het berekeningsresultaat wordt gebruikt.
    KVI 16/1/2002}

  { Important note about DLL memory management: ShareMem must be the
  first unit in your library's USES clause AND your project's (select
  Project-View Source) USES clause if your DLL exports any procedures or
  functions that pass strings as parameters or function results. This
  applies to all strings passed to and from your DLL--even those that
  are nested in records and classes. ShareMem is the interface unit to
  the BORLNDMM.DLL shared memory manager, which must be deployed along
  with your DLL. To avoid using BORLNDMM.DLL, pass string information
  using PChar or ShortString parameters. }

uses
  ShareMem,
  windows, SysUtils, Classes, LargeArrays,
  ExtParU, USpeedProc, uDCfunc,UdsModel, UdsModelS, xyTable, DUtils, uError;

Const
  cModelID      = 301;  {-Uniek modelnummer}

  {-Beschrijving van de array met afhankelijke variabelen}
  cNrOfDepVar   = 1;  {-Lengte van de array met afhankelijke variabelen}
  cFloResult    = 1;  {-Het berekeningsresultaat van 1-v.d. invoermodellen}

  {-Aantal keren dat een discontinuiteitsfunctie wordt aangeroepen in de procedure met
    snelheidsvergelijkingen (DerivsProc)}
  nDC = 0;
  
  cMaxNrOfFloFiles = 5;

  {-Variabelen die samenhangen met het aanroepen van het model vanuit de Shell}
  cnRP    = cMaxNrOfFloFiles + 1;
            {-Aantal RP-tijdreeksen die door de Shell moeten worden aange-
            leverd (in de externe parameter Array EP (element EP[ indx-1 ]))}
  cnSQ    = 0;   {-Idem punt-tijdreeksen}
  cnRQ    = 0;   {-Idem lijn-tijdreeksen}

  {-Beschrijving van het eerste element van de externe parameter-array (EP[cEP0])}
  cNrXIndepTblsInEP0 = 3;  {-Aantal XIndep-tables in EP[cEP0]}
  cNrXdepTblsInEP0   = 0;  {-Aantal Xdep-tables   in EP[cEP0]}
  {-Nummering van de xIndep-tabellen in EP[cEP0]. De nummers 0&1 zijn gereserveerd}
  cTb_MinMaxValKeys   = 2;

  {-Beschrijving van het tweede element van de externe parameter-array (EP[cEP1])}
  {-Opmerking: table 0 van de xIndep-tabellen is gereserveerd}
  {-Nummering van de xdep-tabellen in EP[cEP1]}
  cTb_KeyVal = cnRP-1; {-De key staat altijd in de laatste RP-set}

  {-Model specifieke fout-codes}
  cInvld_KeyValue = -9900;

var
  Indx: Integer; {-Door de Boot-procedure moet de waarde van deze index worden ingevuld,
                   zodat de snelheidsprocedure 'weet' waar (op de externe parameter-array)
				   hij zijn gegevens moet zoeken}
  ModelProfile: TModelProfile;
                 {-Object met met daarin de status van de discontinuiteitsfuncties
				   (zie nDC) }

  {-Geldige range van key-/parameter/initiele waarden. De waarden van deze  variabelen moeten
    worden ingevuld door de Boot-procedure}
  cMin_KeyValue, cMax_KeyValue : Integer;
Procedure MyDllProc( Reason: Integer );
begin
  if Reason = DLL_PROCESS_DETACH then begin {-DLL is unloading}
    {-Cleanup code here}
	if ( nDC > 0 ) then
      ModelProfile.Free;
  end;
end;

Procedure DerivsProc( var x: Double; var y, dydx: TLargeRealArray;
                      var EP: TExtParArray; var Direction: TDirection;
                      var Context: Tcontext; var aModelProfile: PModelProfile; var IErr: Integer );
{-Deze procedure verschaft de array met afgeleiden 'dydx',
  gegeven het tijdstip 'x' en
  de toestand die beschreven wordt door de array 'y' en
  de externe condities die beschreven worden door de 'external parameter-array EP'.
  Als er geen fout op is getreden bij de berekening van 'dydx' dan wordt in deze procedure
  de variabele 'IErr' gelijk gemaakt aan de constante 'cNoError'.
  Opmerking: in de array 'y' staan dus de afhankelijke variabelen, terwijl 'x' de
  onafhankelijke variabele is}
var
  KeyValue: Integer; {-De 'sleutel-waarde' (=key). Deze waarde bepaalt van welk
                       model (1-5) het berekeningsresultaat wordt gebruikt.}
  i: Integer;

Function GetFloValueFromShell( const KeyValue: Integer; const x: Double ): Double;
begin
  with EP[ indx-1 ].xDep do
    Result := Items[ KeyValue-1 ].EstimateY( x, Direction );
end;

Function SetKeyValue( var IErr: Integer ): Boolean;
  Function GetKeyValue( const x: Double ): Integer;
  begin
    with EP[ indx-1 ].xDep do
      Result := Trunc( Items[ cTb_KeyVal ].EstimateY( x, Direction ) );
  end;
begin {-Function SetKeyValue}
  Result := False;
  KeyValue := GetKeyValue( x );
  if ( KeyValue < cMin_KeyValue ) or ( KeyValue > cMax_KeyValue ) then begin
    IErr := cInvld_KeyValue; Exit;
  end;
  Result := True;
end; {-Function SetKeyValue}

begin
  IErr := cUnknownError;
  for i := 1 to cNrOfDepVar do {-Default speed = 0}
    dydx[ i ] := 0;

  {-Geef de aanroepende procedure een handvat naar het ModelProfiel}
  if ( nDC > 0 ) then
    aModelProfile := @ModelProfile
  else
    aModelProfile := NIL;

  if ( Context = UpdateYstart ) then begin {-Run fase 1}
      IErr := cNoError;
  end else begin {-Run fase 2}
    if not SetKeyValue( IErr ) then
      exit;
    {-Bereken de array met afgeleiden 'dydx'}
    dydx[ cFloResult ] := GetFloValueFromShell( KeyValue, x );
  end;
end; {-DerivsProc}

Function DefaultBootEP( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Initialiseer de meest elementaire gegevens van het model. Shell-gegevens worden door deze
    procedure NIET verwerkt}
Procedure SetMinMaxKeyAndParValues;
begin
  with EP[ cEP0 ].xInDep.Items[ cTb_MinMaxValKeys ] do begin
    cMin_KeyValue := Trunc( GetValue( 1, 1 ) ); {rij, kolom}
    cMax_KeyValue := Trunc( GetValue( 1, 2 ) );
  end;
end;
Begin
  Result := DefaultBootEPFromTextFile( EpDir, BootEpArrayOption, cModelID, cNrOfDepVar, nDC, cNrXIndepTblsInEP0,
                                       cNrXdepTblsInEP0, Indx, EP );
  if ( Result = cNoError ) then
    SetMinMaxKeyAndParValues;
end;

Function TestBootEP( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Deze boot-procedure verwerkt alle basisgegevens van het model en leest de Shell-gegevens
    uit een bestand. Na initialisatie met deze boot-procedure is het model dus gereed om
	'te draaien'. Deze procedure kan dus worden gebruikt om het model 'los' van de Shell te
	testen}
Begin
  Result := DefaultBootEP( EpDir, BootEpArrayOption, EP );
  if ( Result <> cNoError ) then
    exit;
  Result := DefaultTestBootEPFromTextFile( EpDir, BootEpArrayOption, cModelID, cnRP + cnSQ + cnRQ, Indx, EP );
  if ( Result <> cNoError ) then
    exit;
  SetReadyToRun( EP);
end;

Function BootEPForShell( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Deze procedure maakt het model gereed voor Shell-gebruik.
    De xDep-tables in EP[ indx-1 ] worden door deze procedure NIET geinitialiseerd omdat deze
	gegevens door de Shell worden verschaft }
begin
  Result := DefaultBootEP( EpDir, cBootEPFromTextFile, EP );
  if ( Result = cNoError ) then
    Result := DefaultBootEPForShell( cnRP, cnSQ, cnRQ, Indx, EP );
end;

Exports DerivsProc       index cModelIndxForTDSmodels, {999}
        DefaultBootEP    index cBoot0, {1}
        TestBootEP       index cBoot1, {2}
        BootEPForShell   index cBoot2; {3}

begin
  {-Dit zgn. 'DLL-Main-block' wordt uitgevoerd als de DLL voor het eerst in het geheugen wordt
    gezet (Reason = DLL_PROCESS_ATTACH)}
  DLLProc := @MyDllProc;
  Indx := cBootEPArrayVariantIndexUnknown;
  if ( nDC > 0 ) then
    ModelProfile := TModelProfile.Create( nDC );  
end.
