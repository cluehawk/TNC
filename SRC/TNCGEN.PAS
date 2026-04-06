unit TNCGen;

interface

uses
  TNCDef,
  TNCRand;

procedure InitGame(var G: TGameState);
function CanGenerateCell(const G: TGameState; X, Y: Byte): Boolean;
function GenerateCell(var G: TGameState; X, Y: Byte): Boolean;

implementation

type
  TCandidate = record
    Kind: TTileKind;
    Rot: Byte;
    Weight: Byte;
  end;

function ShapeBagIndex(Kind: TTileKind): Byte;
begin
  case Kind of
    tkStraight:  ShapeBagIndex := 1;
    tkCorner:    ShapeBagIndex := 2;
    tkTJunction: ShapeBagIndex := 3;
  else
    ShapeBagIndex := 4;
  end;
end;

function ShapeWeight(const G: TGameState; Kind: TTileKind): Byte;
begin
  ShapeWeight := G.ShapeBag[ShapeBagIndex(Kind)];
end;

procedure SetStartCell(var G: TGameState; X, Y: Byte);
begin
  ClearCell(G.Board[X, Y]);
  G.Board[X, Y].Kind := tkStart;
  G.Board[X, Y].Rot := 0;
  G.Board[X, Y].Feature := ftNone;
  G.Board[X, Y].Flags := [cfPresent];
end;

procedure ResetBags(var G: TGameState);
begin
  G.ShapeBag[1] := 26;
  G.ShapeBag[2] := 30;
  G.ShapeBag[3] := 24;
  G.ShapeBag[4] := 16;

  G.FeatureKeys := 6;
  G.FeatureGates := 3;
  G.FeatureCrumbles := 12;
  G.FeatureMonsters := 8;
end;

function AxisDistance(A, B, Size: Byte): Byte;
var
  D1, D2: Byte;
begin
  if A > B then
    D1 := A - B
  else
    D1 := B - A;
  D2 := Size - D1;
  if D1 < D2 then
    AxisDistance := D1
  else
    AxisDistance := D2;
end;

function NearStartTile(const G: TGameState; X, Y: Byte): Boolean;
var
  SX, SY: Byte;
begin
  NearStartTile := False;
  for SX := 0 to BoardW - 1 do
    for SY := 0 to BoardH - 1 do
      if IsPresent(G.Board[SX, SY]) and (G.Board[SX, SY].Kind = tkStart) then
        if (AxisDistance(X, SX, BoardW) + AxisDistance(Y, SY, BoardH)) <= 3 then
        begin
          NearStartTile := True;
          Exit;
        end;
end;

function FarEnoughFromStarts(const G: TGameState; X, Y: Byte; Count: Byte): Boolean;
var
  I: Byte;
  Dist: Byte;
begin
  FarEnoughFromStarts := True;
  if Count = 0 then
    Exit;
  for I := 0 to Count - 1 do
  begin
    Dist := AxisDistance(X, G.Prisoners[I].X, BoardW) + AxisDistance(Y, G.Prisoners[I].Y, BoardH);
    if Dist < 6 then
    begin
      FarEnoughFromStarts := False;
      Exit;
    end;
  end;
end;

function CellWouldLegalOpen(const G: TGameState; X, Y: Byte; Mask: Byte): Boolean;
var
  D: TDirection;
  NX, NY: Byte;
  NCell: TCell;
begin
  CellWouldLegalOpen := True;
  for D := dirNorth to dirWest do
  begin
    NX := WrapX(Integer(X) + DirX[D]);
    NY := WrapY(Integer(Y) + DirY[D]);
    NCell := G.Board[NX, NY];
    if IsPresent(NCell) then
    begin
      if CellOpen(NCell, OppositeDir(D)) then
      begin
        if (Mask and DirMask(D)) = 0 then
        begin
          CellWouldLegalOpen := False;
          Exit;
        end;
      end
      else if (Mask and DirMask(D)) <> 0 then
      begin
        CellWouldLegalOpen := False;
        Exit;
      end;
    end;
  end;
end;

function CandidateLegal(const G: TGameState; X, Y: Byte; Kind: TTileKind; Rot: Byte): Boolean;
begin
  CandidateLegal := CellWouldLegalOpen(G, X, Y, OpenMask(Kind, Rot));
end;

function CanGenerateCell(const G: TGameState; X, Y: Byte): Boolean;
var
  Kind: TTileKind;
  Rot, MaxRot: Byte;
begin
  CanGenerateCell := False;
  if (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
    Exit;
  if IsPresent(G.Board[X, Y]) then
    Exit;

  for Kind := tkStraight to tkCross do
    if ShapeWeight(G, Kind) > 0 then
    begin
      if Kind = tkStraight then
        MaxRot := 1
      else if Kind = tkCross then
        MaxRot := 0
      else
        MaxRot := 3;
      for Rot := 0 to MaxRot do
        if CandidateLegal(G, X, Y, Kind, Rot) then
        begin
          CanGenerateCell := True;
          Exit;
        end;
    end;
end;

function FeatureAllowed(const G: TGameState; X, Y: Byte; Feature: TFeature): Boolean;
begin
  FeatureAllowed := True;
  case Feature of
    ftKey, ftGate, ftMonster:
      if NearStartTile(G, X, Y) then
        FeatureAllowed := False;
    ftCrumbleFresh:
      FeatureAllowed := True;
  end;
end;

function ChooseFeature(var G: TGameState; X, Y: Byte): TFeature;
var
  PlainWeight: Word;
  TotalWeight: Word;
  Roll: Word;
begin
  PlainWeight := 1;
  if G.DrawsRemaining > (G.FeatureKeys + G.FeatureGates + G.FeatureCrumbles + G.FeatureMonsters) then
    PlainWeight := G.DrawsRemaining - (G.FeatureKeys + G.FeatureGates + G.FeatureCrumbles + G.FeatureMonsters);

  TotalWeight := PlainWeight;
  if (G.FeatureKeys > 0) and FeatureAllowed(G, X, Y, ftKey) then
    Inc(TotalWeight, G.FeatureKeys);
  if (G.FeatureGates > 0) and FeatureAllowed(G, X, Y, ftGate) then
    Inc(TotalWeight, G.FeatureGates);
  if (G.FeatureCrumbles > 0) and FeatureAllowed(G, X, Y, ftCrumbleFresh) then
    Inc(TotalWeight, G.FeatureCrumbles);
  if (G.FeatureMonsters > 0) and FeatureAllowed(G, X, Y, ftMonster) then
    Inc(TotalWeight, G.FeatureMonsters);

  Roll := RandomRange(G.RNGSeed, TotalWeight);
  if Roll < PlainWeight then
  begin
    ChooseFeature := ftNone;
    Exit;
  end;
  Dec(Roll, PlainWeight);

  if (G.FeatureKeys > 0) and FeatureAllowed(G, X, Y, ftKey) then
  begin
    if Roll < G.FeatureKeys then
    begin
      Dec(G.FeatureKeys);
      ChooseFeature := ftKey;
      Exit;
    end;
    Dec(Roll, G.FeatureKeys);
  end;

  if (G.FeatureGates > 0) and FeatureAllowed(G, X, Y, ftGate) then
  begin
    if Roll < G.FeatureGates then
    begin
      Dec(G.FeatureGates);
      ChooseFeature := ftGate;
      Exit;
    end;
    Dec(Roll, G.FeatureGates);
  end;

  if (G.FeatureCrumbles > 0) and FeatureAllowed(G, X, Y, ftCrumbleFresh) then
  begin
    if Roll < G.FeatureCrumbles then
    begin
      Dec(G.FeatureCrumbles);
      ChooseFeature := ftCrumbleFresh;
      Exit;
    end;
    Dec(Roll, G.FeatureCrumbles);
  end;

  if (G.FeatureMonsters > 0) and FeatureAllowed(G, X, Y, ftMonster) then
  begin
    if Roll < G.FeatureMonsters then
    begin
      Dec(G.FeatureMonsters);
      ChooseFeature := ftMonster;
      Exit;
    end;
  end;

  ChooseFeature := ftNone;
end;

function GenerateCell(var G: TGameState; X, Y: Byte): Boolean;
var
  Candidates: array[0..15] of TCandidate;
  Count: Byte;
  TotalWeight: Word;
  Roll: Word;
  I: Byte;
  Kind: TTileKind;
  Rot, MaxRot: Byte;
begin
  GenerateCell := False;
  if (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
    Exit;
  if IsPresent(G.Board[X, Y]) then
  begin
    GenerateCell := True;
    Exit;
  end;

  Count := 0;
  TotalWeight := 0;
  for Kind := tkStraight to tkCross do
    if ShapeWeight(G, Kind) > 0 then
    begin
      if Kind = tkStraight then
        MaxRot := 1
      else if Kind = tkCross then
        MaxRot := 0
      else
        MaxRot := 3;

      for Rot := 0 to MaxRot do
        if CandidateLegal(G, X, Y, Kind, Rot) then
        begin
          Candidates[Count].Kind := Kind;
          Candidates[Count].Rot := Rot;
          Candidates[Count].Weight := ShapeWeight(G, Kind);
          Inc(TotalWeight, Candidates[Count].Weight);
          Inc(Count);
        end;
    end;

  if Count = 0 then
    Exit;

  Roll := RandomRange(G.RNGSeed, TotalWeight);
  I := 0;
  while I < Count do
  begin
    if Roll < Candidates[I].Weight then
      Break;
    Dec(Roll, Candidates[I].Weight);
    Inc(I);
  end;
  if I >= Count then
    I := Count - 1;

  ClearCell(G.Board[X, Y]);
  G.Board[X, Y].Kind := Candidates[I].Kind;
  G.Board[X, Y].Rot := Candidates[I].Rot;
  G.Board[X, Y].Feature := ChooseFeature(G, X, Y);
  G.Board[X, Y].Flags := [cfPresent];
  G.Board[X, Y].LastLitTurn := 0;

  Dec(G.ShapeBag[ShapeBagIndex(Candidates[I].Kind)]);
  Dec(G.DrawsRemaining);
  GenerateCell := True;
end;

procedure ClearBoard(var G: TGameState);
var
  X, Y: Byte;
begin
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      ClearCell(G.Board[X, Y]);
end;

procedure InitGame(var G: TGameState);
var
  I: Byte;
  X, Y: Byte;
begin
  FillChar(G, SizeOf(G), 0);
  ClearBoard(G);
  ClearLog(G);
  InitSeedFromClock(G.RNGSeed);
  G.DrawsRemaining := InitialDraws;
  G.ActiveIndex := 0;
  G.ViewIndex := 0;
  G.TurnNumber := 1;
  G.Phase := gpMaze;
  G.LostKeys := 0;
  G.LostGates := 0;
  G.FlickerCursor := 0;
  ResetBags(G);

  for I := 0 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].Lit := True;
    G.Prisoners[I].HasKey := False;
    G.Prisoners[I].Falling := False;
    G.Prisoners[I].Alive := True;
    G.Prisoners[I].BonusAction := False;
    G.Prisoners[I].Nerve := StartNerve;
  end;

  for I := 0 to PrisonerCount - 1 do
  begin
    repeat
      X := RandomRange(G.RNGSeed, BoardW);
      Y := RandomRange(G.RNGSeed, BoardH);
    until (not IsPresent(G.Board[X, Y])) and FarEnoughFromStarts(G, X, Y, I);

    SetStartCell(G, X, Y);
    G.Prisoners[I].X := X;
    G.Prisoners[I].Y := Y;
  end;

  AddLog(G, 'Four prisoners wake far apart in the dark.');
  AddLog(G, 'I/J/K/L move. S stays. N spends nerve. TAB changes focus.');
end;

end.
