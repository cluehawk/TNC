unit TNCDef;

interface

const
  BoardW       = 18;
  BoardH       = 12;
  PrisonerCount = 4;
  MaxLogLines  = 5;
  StartNerve   = 3;
  InitialDraws = 96;

type
  TDirection = (dirNorth, dirEast, dirSouth, dirWest);

  TTileKind = (tkVoid, tkStart, tkStraight, tkCorner, tkTJunction, tkCross, tkPit);
  TFeature  = (ftNone, ftKey, ftGate, ftCrumbleFresh, ftCrumbleArmed, ftMonster);
  TCellFlag = (cfPresent, cfPermanent, cfLit, cfOccupied);
  TCellFlags = set of TCellFlag;
  TGamePhase = (gpMaze, gpFinal, gpWin, gpLoss);

  TCell = record
    Kind: TTileKind;
    Rot: Byte;
    Feature: TFeature;
    Flags: TCellFlags;
    LastLitTurn: Word;
  end;

  TPrisoner = record
    X: Byte;
    Y: Byte;
    Lit: Boolean;
    HasKey: Boolean;
    Falling: Boolean;
    Alive: Boolean;
    BonusAction: Boolean;
    Nerve: Byte;
  end;

  TMessageStr = string[62];

  TGameState = record
    Board: array[0..BoardW - 1, 0..BoardH - 1] of TCell;
    Prisoners: array[0..PrisonerCount - 1] of TPrisoner;
    ActiveIndex: Byte;
    ViewIndex: Byte;
    TurnNumber: Word;
    DrawsRemaining: Word;
    Phase: TGamePhase;
    RNGSeed: Word;
    ShapeBag: array[1..4] of Byte;
    FeatureKeys: Byte;
    FeatureGates: Byte;
    FeatureCrumbles: Byte;
    FeatureMonsters: Byte;
    LostKeys: Byte;
    LostGates: Byte;
    LogHead: Byte;
    LogCount: Byte;
    Messages: array[0..MaxLogLines - 1] of TMessageStr;
    FlickerCursor: Word;
  end;

const
  DirX: array[TDirection] of Integer = (0, 1, 0, -1);
  DirY: array[TDirection] of Integer = (-1, 0, 1, 0);

function WrapX(I: Integer): Byte;
function WrapY(I: Integer): Byte;
function OppositeDir(D: TDirection): TDirection;
function DirMask(D: TDirection): Byte;
function RotateMask(Mask: Byte; Rot: Byte): Byte;
function OpenMask(Kind: TTileKind; Rot: Byte): Byte;
function CellOpen(const Cell: TCell; D: TDirection): Boolean;
function IsPresent(const Cell: TCell): Boolean;
function IsPassable(const Cell: TCell): Boolean;
function IsNearStartArea(X, Y: Byte): Boolean;
function PrisonerName(Index: Byte): string;
function DirName(D: TDirection): string;
function PhaseName(P: TGamePhase): string;
function LogMessage(const G: TGameState; FromOldest: Byte): TMessageStr;

procedure ClearCell(var Cell: TCell);
procedure ClearLog(var G: TGameState);
procedure AddLog(var G: TGameState; S: string);

implementation

function WrapX(I: Integer): Byte;
begin
  while I < 0 do
    Inc(I, BoardW);
  while I >= BoardW do
    Dec(I, BoardW);
  WrapX := I;
end;

function WrapY(I: Integer): Byte;
begin
  while I < 0 do
    Inc(I, BoardH);
  while I >= BoardH do
    Dec(I, BoardH);
  WrapY := I;
end;

function OppositeDir(D: TDirection): TDirection;
begin
  case D of
    dirNorth: OppositeDir := dirSouth;
    dirEast:  OppositeDir := dirWest;
    dirSouth: OppositeDir := dirNorth;
  else
    OppositeDir := dirEast;
  end;
end;

function DirMask(D: TDirection): Byte;
begin
  case D of
    dirNorth: DirMask := 1;
    dirEast:  DirMask := 2;
    dirSouth: DirMask := 4;
  else
    DirMask := 8;
  end;
end;

function RotateMask(Mask: Byte; Rot: Byte): Byte;
var
  I: Byte;
begin
  Rot := Rot mod 4;
  for I := 1 to Rot do
    Mask := ((Mask shl 1) and 15) or ((Mask shr 3) and 1);
  RotateMask := Mask;
end;

function OpenMask(Kind: TTileKind; Rot: Byte): Byte;
begin
  case Kind of
    tkVoid:      OpenMask := 0;
    tkStart:     OpenMask := 15;
    tkStraight:  OpenMask := RotateMask(5, Rot mod 2);
    tkCorner:    OpenMask := RotateMask(3, Rot mod 4);
    tkTJunction: OpenMask := RotateMask(7, Rot mod 4);
    tkCross:     OpenMask := 15;
    tkPit:       OpenMask := 0;
  else
    OpenMask := 0;
  end;
end;

function CellOpen(const Cell: TCell; D: TDirection): Boolean;
begin
  CellOpen := (OpenMask(Cell.Kind, Cell.Rot) and DirMask(D)) <> 0;
end;

function IsPresent(const Cell: TCell): Boolean;
begin
  IsPresent := cfPresent in Cell.Flags;
end;

function IsPassable(const Cell: TCell): Boolean;
begin
  IsPassable := IsPresent(Cell) and (Cell.Kind <> tkPit);
end;

function IsNearStartArea(X, Y: Byte): Boolean;
begin
  IsNearStartArea := (((X >= 6) and (X <= 11)) and ((Y >= 3) and (Y <= 8)));
end;

function PrisonerName(Index: Byte): string;
begin
  case Index of
    0: PrisonerName := 'P1';
    1: PrisonerName := 'P2';
    2: PrisonerName := 'P3';
  else
    PrisonerName := 'P4';
  end;
end;

function DirName(D: TDirection): string;
begin
  case D of
    dirNorth: DirName := 'north';
    dirEast:  DirName := 'east';
    dirSouth: DirName := 'south';
  else
    DirName := 'west';
  end;
end;

function PhaseName(P: TGamePhase): string;
begin
  case P of
    gpMaze:  PhaseName := 'MAZE';
    gpFinal: PhaseName := 'FINAL';
    gpWin:   PhaseName := 'WIN';
  else
    PhaseName := 'LOSS';
  end;
end;

procedure ClearCell(var Cell: TCell);
begin
  Cell.Kind := tkVoid;
  Cell.Rot := 0;
  Cell.Feature := ftNone;
  Cell.Flags := [];
  Cell.LastLitTurn := 0;
end;

procedure ClearLog(var G: TGameState);
var
  I: Byte;
begin
  G.LogHead := 0;
  G.LogCount := 0;
  for I := 0 to MaxLogLines - 1 do
    G.Messages[I] := '';
end;

procedure AddLog(var G: TGameState; S: string);
begin
  if Length(S) > 62 then
    S := Copy(S, 1, 62);
  G.Messages[G.LogHead] := S;
  G.LogHead := (G.LogHead + 1) mod MaxLogLines;
  if G.LogCount < MaxLogLines then
    Inc(G.LogCount);
end;

function LogMessage(const G: TGameState; FromOldest: Byte): TMessageStr;
var
  Index: Integer;
begin
  if FromOldest >= G.LogCount then
  begin
    LogMessage := '';
    Exit;
  end;

  Index := G.LogHead - G.LogCount + FromOldest;
  while Index < 0 do
    Inc(Index, MaxLogLines);
  while Index >= MaxLogLines do
    Dec(Index, MaxLogLines);
  LogMessage := G.Messages[Index];
end;

end.
