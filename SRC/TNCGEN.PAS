unit TNCGen;

interface

uses
  Crt,
  TNCDef,
  TNCRand;

procedure InitGame(var G: TGameState);
function CanGenerateCell(const G: TGameState; X, Y: Byte): Boolean;
function GenerateCell(var G: TGameState; X, Y: Byte): Boolean;
procedure DiscardDrawTiles(var G: TGameState; Count: Byte);

implementation

procedure SetStartCell(var G: TGameState; X, Y: Byte);
begin
  ClearCell(G.Board[X, Y]);
  G.Board[X, Y].Kind := tkStart;
  G.Board[X, Y].Rot := 0;
  G.Board[X, Y].Feature := ftNone;
  G.Board[X, Y].Flags := [cfPresent];
end;

procedure ClearDrawTile(var T: TDrawTile);
begin
  T.Kind := tkVoid;
  T.Feature := ftNone;
end;

procedure AddFeatureCounter(var G: TGameState; Feature: TFeature);
begin
  case Feature of
    ftKey: Inc(G.FeatureKeys);
    ftGate: Inc(G.FeatureGates);
    ftCrumbleFresh, ftCrumbleArmed: Inc(G.FeatureCrumbles);
    ftMonster: Inc(G.FeatureMonsters);
  end;
end;

procedure RemoveFeatureCounter(var G: TGameState; Feature: TFeature; Lost: Boolean);
begin
  case Feature of
    ftKey:
      begin
        if G.FeatureKeys > 0 then
          Dec(G.FeatureKeys);
        if Lost then
          Inc(G.LostKeys);
      end;
    ftGate:
      begin
        if G.FeatureGates > 0 then
          Dec(G.FeatureGates);
        if Lost then
          Inc(G.LostGates);
      end;
    ftCrumbleFresh, ftCrumbleArmed:
      if G.FeatureCrumbles > 0 then
        Dec(G.FeatureCrumbles);
    ftMonster:
      if G.FeatureMonsters > 0 then
        Dec(G.FeatureMonsters);
  end;
end;

procedure PushDrawTile(var G: TGameState; var Count: Byte; Kind: TTileKind; Feature: TFeature);
begin
  if Count >= MaxDrawTiles then
    Exit;
  Inc(Count);
  G.TileStack[Count].Kind := Kind;
  G.TileStack[Count].Feature := Feature;
  AddFeatureCounter(G, Feature);
end;

procedure SwapDrawTiles(var A, B: TDrawTile);
var
  T: TDrawTile;
begin
  T := A;
  A := B;
  B := T;
end;

procedure ShuffleStackRange(var G: TGameState; First, Last: Byte);
var
  I, J: Byte;
begin
  if Last <= First then
    Exit;
  for I := First to Last do
  begin
    J := First + RandomRange(G.RNGSeed, Last - First + 1);
    SwapDrawTiles(G.TileStack[I], G.TileStack[J]);
  end;
end;

procedure BuildDrawStack(var G: TGameState);
var
  I: Byte;
  Count: Byte;
  OpeningFirst: Byte;
begin
  Count := 0;
  G.FeatureKeys := 0;
  G.FeatureGates := 0;
  G.FeatureCrumbles := 0;
  G.FeatureMonsters := 0;
  for I := 1 to MaxDrawTiles do
    ClearDrawTile(G.TileStack[I]);

  { Core 1-4 prisoner pool after removing two key tiles.
    Feature tiles keep a simple passage shape until manual tile choice exists. }
  for I := 1 to 8 do
    PushDrawTile(G, Count, tkStraight, ftCrumbleFresh);
  for I := 1 to 26 do
    PushDrawTile(G, Count, tkTJunction, ftNone);
  for I := 1 to 2 do
    PushDrawTile(G, Count, tkTJunction, ftCrumbleFresh);
  for I := 1 to 10 do
    PushDrawTile(G, Count, tkCross, ftNone);
  for I := 1 to 6 do
    PushDrawTile(G, Count, tkTJunction, ftKey);
  for I := 1 to 4 do
    PushDrawTile(G, Count, tkCross, ftGate);
  for I := 1 to 12 do
    PushDrawTile(G, Count, tkCross, ftMonster);

  ShuffleStackRange(G, 1, Count);

  OpeningFirst := Count + 1;
  for I := 1 to 4 do
    PushDrawTile(G, Count, tkTJunction, ftNone);
  for I := 1 to 2 do
    PushDrawTile(G, Count, tkCross, ftNone);
  for I := 1 to 2 do
    PushDrawTile(G, Count, tkStraight, ftCrumbleFresh);
  ShuffleStackRange(G, OpeningFirst, Count);

  G.DrawsRemaining := Count;
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
        if (AxisDistance(X, SX, BoardW) + AxisDistance(Y, SY, BoardH)) <= 1 then
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
    if Dist < 3 then
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

function MaxRotationForKind(Kind: TTileKind): Byte;
begin
  case Kind of
    tkStraight: MaxRotationForKind := 1;
    tkCross:    MaxRotationForKind := 0;
  else
    MaxRotationForKind := 3;
  end;
end;

function DrawTileFits(const G: TGameState; X, Y: Byte; const Tile: TDrawTile; var Rot: Byte): Boolean;
var
  R, MaxRot: Byte;
begin
  DrawTileFits := False;
  MaxRot := MaxRotationForKind(Tile.Kind);
  for R := 0 to MaxRot do
    if CandidateLegal(G, X, Y, Tile.Kind, R) then
    begin
      Rot := R;
      DrawTileFits := True;
      Exit;
    end;
end;

function TileFeatureName(Feature: TFeature): string;
begin
  case Feature of
    ftKey: TileFeatureName := 'key';
    ftGate: TileFeatureName := 'gate';
    ftCrumbleFresh, ftCrumbleArmed: TileFeatureName := 'crumble';
    ftMonster: TileFeatureName := 'wax eater';
  else
    TileFeatureName := 'plain';
  end;
end;

function TileKindName(Kind: TTileKind): string;
begin
  case Kind of
    tkStraight:  TileKindName := 'straight';
    tkCorner:    TileKindName := 'corner';
    tkTJunction: TileKindName := 'T';
    tkCross:     TileKindName := '4-way';
  else
    TileKindName := 'tile';
  end;
end;

function RotationMaskText(Kind: TTileKind; Rot: Byte): string;
var
  Mask: Byte;
  S: string[4];
begin
  Mask := OpenMask(Kind, Rot);
  S := '';
  if (Mask and DirMask(dirNorth)) <> 0 then
    S := S + 'N';
  if (Mask and DirMask(dirEast)) <> 0 then
    S := S + 'E';
  if (Mask and DirMask(dirSouth)) <> 0 then
    S := S + 'S';
  if (Mask and DirMask(dirWest)) <> 0 then
    S := S + 'W';
  RotationMaskText := S;
end;

function PreviewBoxChar(Code: Byte): Char;
begin
  PreviewBoxChar := Chr(Code);
end;

function PreviewPassageGlyph(Kind: TTileKind; Rot: Byte): Char;
var
  Mask: Byte;
begin
  Mask := OpenMask(Kind, Rot);
  case Mask of
     3: PreviewPassageGlyph := PreviewBoxChar(192);
     5: PreviewPassageGlyph := PreviewBoxChar(179);
     6: PreviewPassageGlyph := PreviewBoxChar(218);
     7: PreviewPassageGlyph := PreviewBoxChar(195);
     9: PreviewPassageGlyph := PreviewBoxChar(217);
    10: PreviewPassageGlyph := PreviewBoxChar(196);
    11: PreviewPassageGlyph := PreviewBoxChar(193);
    12: PreviewPassageGlyph := PreviewBoxChar(191);
    13: PreviewPassageGlyph := PreviewBoxChar(180);
    14: PreviewPassageGlyph := PreviewBoxChar(194);
    15: PreviewPassageGlyph := PreviewBoxChar(197);
  else
    PreviewPassageGlyph := '?';
  end;
end;

function PreviewFeatureGlyph(Kind: TTileKind; Feature: TFeature): Char;
begin
  case Feature of
    ftKey: PreviewFeatureGlyph := 'K';
    ftGate: PreviewFeatureGlyph := 'G';
    ftCrumbleFresh, ftCrumbleArmed: PreviewFeatureGlyph := '*';
    ftMonster: PreviewFeatureGlyph := 'W';
  else
    if Kind = tkStart then
      PreviewFeatureGlyph := 'S'
    else
      PreviewFeatureGlyph := ' ';
  end;
end;

procedure DrawPreviewTile(X, Y: Byte; const Tile: TDrawTile; Rot: Byte);
var
  S: string[6];
  Mask: Byte;
begin
  S := '      ';
  S[3] := PreviewPassageGlyph(Tile.Kind, Rot);
  S[4] := PreviewFeatureGlyph(Tile.Kind, Tile.Feature);
  GotoXY(3 + X * 6, 3 + Y * 2);
  Write(S);

  S := '      ';
  Mask := OpenMask(Tile.Kind, Rot);
  if (Mask and DirMask(dirNorth)) <> 0 then
    S[3] := '|';
  if (Mask and DirMask(dirSouth)) <> 0 then
    S[4] := '|';
  if (Mask and DirMask(dirWest)) <> 0 then
    S[2] := '-';
  if (Mask and DirMask(dirEast)) <> 0 then
    S[5] := '-';
  GotoXY(3 + X * 6, 4 + Y * 2);
  Write(S);
end;

procedure ClearPromptLines;
begin
  GotoXY(3, 23);
  Write('                                                                          ');
  GotoXY(3, 24);
  Write('                                                                          ');
end;

function ChooseRotation(var G: TGameState; X, Y: Byte; const Tile: TDrawTile; DefaultRot: Byte): Byte;
var
  Rot, MaxRot: Byte;
  Ch: Char;
begin
  Rot := DefaultRot;
  MaxRot := MaxRotationForKind(Tile.Kind);
  if not G.PromptPlacement then
  begin
    ChooseRotation := Rot;
    Exit;
  end;

  repeat
    DrawPreviewTile(X, Y, Tile, Rot);
    ClearPromptLines;
    GotoXY(3, 23);
    Write('Draw ', TileKindName(Tile.Kind), ' ', TileFeatureName(Tile.Feature),
          ' at ', X + 1, ',', Y + 1, '.');
    GotoXY(3, 24);
    if MaxRot = 0 then
      Write('ENTER place   Open: ', RotationMaskText(Tile.Kind, Rot))
    else
      Write('R rotate  ENTER place   Open: ', RotationMaskText(Tile.Kind, Rot));
    Ch := ReadKey;
    if Ch = #0 then
      Ch := ReadKey
    else
    begin
      Ch := UpCase(Ch);
      if (Ch = 'R') and (MaxRot > 0) then
      begin
        repeat
          Rot := (Rot + 1) mod (MaxRot + 1);
        until CandidateLegal(G, X, Y, Tile.Kind, Rot);
      end;
    end;
  until (Ch = #13) or (Ch = ' ');

  ClearPromptLines;
  ChooseRotation := Rot;
end;

function DrawTopTile(var G: TGameState; var Tile: TDrawTile; Lost: Boolean): Boolean;
begin
  DrawTopTile := False;
  if G.DrawsRemaining = 0 then
    Exit;
  Tile := G.TileStack[G.DrawsRemaining];
  RemoveFeatureCounter(G, Tile.Feature, Lost);
  ClearDrawTile(G.TileStack[G.DrawsRemaining]);
  Dec(G.DrawsRemaining);
  DrawTopTile := True;
end;

procedure DiscardDrawTiles(var G: TGameState; Count: Byte);
var
  I: Byte;
  Tile: TDrawTile;
begin
  for I := 1 to Count do
    if G.DrawsRemaining > 0 then
      DrawTopTile(G, Tile, True);
end;

function CanGenerateCell(const G: TGameState; X, Y: Byte): Boolean;
var
  I: Word;
  Rot: Byte;
begin
  CanGenerateCell := False;
  if (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
    Exit;
  if IsPresent(G.Board[X, Y]) then
  begin
    CanGenerateCell := False;
    Exit;
  end;

  for I := G.DrawsRemaining downto 1 do
    if DrawTileFits(G, X, Y, G.TileStack[I], Rot) then
    begin
      CanGenerateCell := True;
      Exit;
    end;
end;

function GenerateCell(var G: TGameState; X, Y: Byte): Boolean;
var
  Tile: TDrawTile;
  Rot: Byte;
begin
  GenerateCell := False;
  if (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
    Exit;
  if IsPresent(G.Board[X, Y]) then
  begin
    GenerateCell := True;
    Exit;
  end;

  while G.DrawsRemaining > 0 do
  begin
    Tile := G.TileStack[G.DrawsRemaining];
    if DrawTileFits(G, X, Y, Tile, Rot) then
    begin
      if not DrawTopTile(G, Tile, False) then
        Exit;
      Rot := ChooseRotation(G, X, Y, Tile, Rot);

      ClearCell(G.Board[X, Y]);
      G.Board[X, Y].Kind := Tile.Kind;
      G.Board[X, Y].Rot := Rot;
      G.Board[X, Y].Feature := Tile.Feature;
      G.Board[X, Y].Flags := [cfPresent];
      G.Board[X, Y].LastLitTurn := 0;

      GenerateCell := True;
      Exit;
    end
    else
    begin
      DrawTopTile(G, Tile, True);
      AddLog(G, 'A drawn tile will not fit and is lost.');
    end;
  end;

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
  I, J, Tmp: Byte;
  BaseX, BaseY, HalfW, HalfH: Byte;
  StartX, StartY: array[0..PrisonerCount - 1] of Byte;
begin
  FillChar(G, SizeOf(G), 0);
  ClearBoard(G);
  ClearLog(G);
  InitSeedFromClock(G.RNGSeed);
  G.DrawsRemaining := 0;
  G.ActiveIndex := 0;
  G.ViewIndex := 0;
  G.TurnNumber := 1;
  G.Phase := gpMaze;
  G.PromptPlacement := False;
  G.LostKeys := 0;
  G.LostGates := 0;
  G.FlickerCursor := 0;
  BuildDrawStack(G);

  for I := 0 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].Lit := True;
    G.Prisoners[I].HasKey := False;
    G.Prisoners[I].Falling := False;
    G.Prisoners[I].Alive := True;
    G.Prisoners[I].BonusAction := False;
    G.Prisoners[I].Nerve := StartNerve;
  end;

  HalfW := BoardW div 2;
  HalfH := BoardH div 2;
  BaseX := RandomRange(G.RNGSeed, HalfW);
  BaseY := RandomRange(G.RNGSeed, HalfH);

  StartX[0] := BaseX;
  StartY[0] := BaseY;
  StartX[1] := WrapX(Integer(BaseX) + HalfW);
  StartY[1] := BaseY;
  StartX[2] := BaseX;
  StartY[2] := WrapY(Integer(BaseY) + HalfH);
  StartX[3] := WrapX(Integer(BaseX) + HalfW);
  StartY[3] := WrapY(Integer(BaseY) + HalfH);

  { Shuffle prisoner assignment without risking an endless retry on 6x6. }
  for I := 0 to PrisonerCount - 1 do
  begin
    J := RandomRange(G.RNGSeed, PrisonerCount);
    Tmp := StartX[I];
    StartX[I] := StartX[J];
    StartX[J] := Tmp;
    Tmp := StartY[I];
    StartY[I] := StartY[J];
    StartY[J] := Tmp;
  end;

  for I := 0 to PrisonerCount - 1 do
  begin
    SetStartCell(G, StartX[I], StartY[I]);
    G.Prisoners[I].X := StartX[I];
    G.Prisoners[I].Y := StartY[I];
  end;

  AddLog(G, 'Four prisoners wake far apart in the dark.');
  AddLog(G, 'I/J/K/L move. S stays. N spends nerve. TAB changes focus.');
end;

end.
