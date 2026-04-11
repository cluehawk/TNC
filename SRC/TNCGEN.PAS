unit TNCGen;

interface

uses
  Crt,
  TNCDef,
  TNCRand;

procedure InitGame(var G: TGameState);
function CanGenerateCell(const G: TGameState; X, Y: Byte; RequiredDir: TDirection): Boolean;
function GenerateCell(var G: TGameState; X, Y: Byte; RequiredDir: TDirection): Boolean;
function PlaceIlluminationTile(var G: TGameState; const Eligible: TBoolGrid;
  const RequiredDirs: TDirGrid): Boolean;
procedure PlaceStartCell(var G: TGameState; X, Y: Byte);
function PlaceFreeTileAt(var G: TGameState; X, Y: Byte): Boolean;
function PlaceFreeTileAtAuto(var G: TGameState; X, Y: Byte): Boolean;
procedure DiscardDrawTiles(var G: TGameState; Count: Byte);
function DrawTopTile(var G: TGameState; var Tile: TDrawTile; Lost: Boolean): Boolean;

implementation

procedure SetPreviewHighlight;
begin
  TextAttr := AttrBlinkInverse;
end;

procedure SetNormalText;
begin
  TextAttr := AttrNormal;
end;

function PreviewScreenY(Y: Byte): Byte;
begin
  if BoardCellScreenY(Y) > 1 then
    PreviewScreenY := BoardCellScreenY(Y) - 1
  else
    PreviewScreenY := BoardCellScreenY(Y);
end;

procedure PlaceStartCell(var G: TGameState; X, Y: Byte);
begin
  ClearCell(G.Board[X, Y]);
  G.Board[X, Y].Kind := tkStart;
  G.Board[X, Y].Rot := 0;
  G.Board[X, Y].Feature := ftNone;
  G.Board[X, Y].Flags := [cfPresent, cfFresh];
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

function CellWouldLegalOpen(const G: TGameState; X, Y: Byte; Mask: Byte; RequiredDir: TDirection): Boolean;
begin
  if (Mask and DirMask(RequiredDir)) = 0 then
  begin
    CellWouldLegalOpen := False;
    Exit;
  end;
  CellWouldLegalOpen := True;
end;

function CandidateLegal(const G: TGameState; X, Y: Byte; Kind: TTileKind; Rot: Byte;
  RequiredDir: TDirection): Boolean;
begin
  CandidateLegal := CellWouldLegalOpen(G, X, Y, OpenMask(Kind, Rot), RequiredDir);
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

function DrawTileFits(const G: TGameState; X, Y: Byte; const Tile: TDrawTile;
  RequiredDir: TDirection; var Rot: Byte): Boolean;
var
  R, MaxRot: Byte;
begin
  DrawTileFits := False;
  MaxRot := MaxRotationForKind(Tile.Kind);
  for R := 0 to MaxRot do
    if CandidateLegal(G, X, Y, Tile.Kind, R, RequiredDir) then
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
  S: string[4];
begin
  S := '    ';
  S[2] := TileGlyph(Tile.Kind, Rot);
  S[3] := PreviewFeatureGlyph(Tile.Kind, Tile.Feature);
  GotoXY(BoardCellScreenX(X), PreviewScreenY(Y));
  SetPreviewHighlight;
  Write(S);
  SetNormalText;
end;

procedure ClearPreviewTile(X, Y: Byte);
begin
  GotoXY(BoardCellScreenX(X), PreviewScreenY(Y));
  Write('    ');
end;

procedure ClearPromptLines;
begin
  GotoXY(3, 23);
  Write('                                                                          ');
  GotoXY(3, 24);
  Write('                                                                          ');
end;

function ChooseRotation(var G: TGameState; X, Y: Byte; const Tile: TDrawTile;
  RequiredDir: TDirection; DefaultRot: Byte): Byte;
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
        until CandidateLegal(G, X, Y, Tile.Kind, Rot, RequiredDir);
      end;
    end;
  until (Ch = #13) or (Ch = ' ');

  ClearPromptLines;
  ChooseRotation := Rot;
end;

function ChooseFreeRotation(var G: TGameState; X, Y: Byte; const Tile: TDrawTile): Byte;
var
  Rot, MaxRot: Byte;
  Ch: Char;
begin
  Rot := 0;
  MaxRot := MaxRotationForKind(Tile.Kind);
  if not G.PromptPlacement then
  begin
    ChooseFreeRotation := Rot;
    Exit;
  end;

  repeat
    DrawPreviewTile(X, Y, Tile, Rot);
    ClearPromptLines;
    GotoXY(3, 23);
    Write('Landing tile: ', TileKindName(Tile.Kind), ' ', TileFeatureName(Tile.Feature), '.');
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
        Rot := (Rot + 1) mod (MaxRot + 1);
    end;
  until (Ch = #13) or (Ch = ' ');

  ClearPreviewTile(X, Y);
  ClearPromptLines;
  ChooseFreeRotation := Rot;
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

function PlaceIlluminationTile(var G: TGameState; const Eligible: TBoolGrid;
  const RequiredDirs: TDirGrid): Boolean;
var
  Tile: TDrawTile;
  Legal: TBoolGrid;
  X, Y, SelX, SelY, OldX, OldY: Byte;
  Count: Byte;
  Rot, TrialRot: Byte;
  Found: Boolean;
  Ch: Char;
begin
  PlaceIlluminationTile := False;
  if (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
    Exit;

  while G.DrawsRemaining > 0 do
  begin
    Tile := G.TileStack[G.DrawsRemaining];
    FillChar(Legal, SizeOf(Legal), 0);
    Count := 0;
    Found := False;

    for Y := 0 to BoardH - 1 do
      for X := 0 to BoardW - 1 do
        if Eligible[X, Y] and DrawTileFits(G, X, Y, Tile, RequiredDirs[X, Y], TrialRot) then
        begin
          Legal[X, Y] := True;
          Inc(Count);
          if not Found then
          begin
            SelX := X;
            SelY := Y;
            Rot := TrialRot;
            Found := True;
          end;
        end;

    if Count = 0 then
    begin
      DrawTopTile(G, Tile, True);
      AddLog(G, 'A drawn tile cannot fit any open space and is lost.');
      Continue;
    end;

    if G.PromptPlacement then
    begin
      repeat
        DrawPreviewTile(SelX, SelY, Tile, Rot);
        ClearPromptLines;
        GotoXY(3, 23);
        Write('Top tile: ', TileKindName(Tile.Kind), ' ', TileFeatureName(Tile.Feature), '.');
        GotoXY(3, 24);
        Write('TAB target  R rotate  ENTER place');
        Ch := ReadKey;
        if Ch = #0 then
          Ch := ReadKey
        else
        begin
          Ch := UpCase(Ch);
          if Ch = #9 then
          begin
            OldX := SelX;
            OldY := SelY;
            repeat
              Inc(SelX);
              if SelX >= BoardW then
              begin
                SelX := 0;
                Inc(SelY);
                if SelY >= BoardH then
                  SelY := 0;
              end;
            until Legal[SelX, SelY];
            ClearPreviewTile(OldX, OldY);
            DrawTileFits(G, SelX, SelY, Tile, RequiredDirs[SelX, SelY], Rot);
          end
          else if Ch = 'R' then
          begin
            repeat
              Rot := (Rot + 1) mod (MaxRotationForKind(Tile.Kind) + 1);
            until CandidateLegal(G, SelX, SelY, Tile.Kind, Rot, RequiredDirs[SelX, SelY]);
          end;
        end;
      until (Ch = #13) or (Ch = ' ');
      ClearPreviewTile(SelX, SelY);
      ClearPromptLines;
    end;

    if not DrawTopTile(G, Tile, False) then
      Exit;

    ClearCell(G.Board[SelX, SelY]);
    G.Board[SelX, SelY].Kind := Tile.Kind;
    G.Board[SelX, SelY].Rot := Rot;
    G.Board[SelX, SelY].Feature := Tile.Feature;
    G.Board[SelX, SelY].Flags := [cfPresent, cfFresh];
    G.Board[SelX, SelY].LastLitTurn := 0;
    PlaceIlluminationTile := True;
    Exit;
  end;
end;

function PlaceFreeTileAt(var G: TGameState; X, Y: Byte): Boolean;
var
  Tile: TDrawTile;
  Rot: Byte;
begin
  PlaceFreeTileAt := False;
  if (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
    Exit;
  if IsPresent(G.Board[X, Y]) then
    Exit;
  if not DrawTopTile(G, Tile, False) then
    Exit;

  Rot := ChooseFreeRotation(G, X, Y, Tile);
  ClearCell(G.Board[X, Y]);
  G.Board[X, Y].Kind := Tile.Kind;
  G.Board[X, Y].Rot := Rot;
  G.Board[X, Y].Feature := Tile.Feature;
  G.Board[X, Y].Flags := [cfPresent, cfFresh];
  G.Board[X, Y].LastLitTurn := 0;
  PlaceFreeTileAt := True;
end;

function PlaceFreeTileAtAuto(var G: TGameState; X, Y: Byte): Boolean;
var
  Tile: TDrawTile;
begin
  PlaceFreeTileAtAuto := False;
  if (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
    Exit;
  if IsPresent(G.Board[X, Y]) then
    Exit;
  if not DrawTopTile(G, Tile, False) then
    Exit;

  ClearCell(G.Board[X, Y]);
  G.Board[X, Y].Kind := Tile.Kind;
  G.Board[X, Y].Rot := 0;
  G.Board[X, Y].Feature := Tile.Feature;
  G.Board[X, Y].Flags := [cfPresent, cfFresh];
  G.Board[X, Y].LastLitTurn := 0;
  PlaceFreeTileAtAuto := True;
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

function CanGenerateCell(const G: TGameState; X, Y: Byte; RequiredDir: TDirection): Boolean;
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
    if DrawTileFits(G, X, Y, G.TileStack[I], RequiredDir, Rot) then
    begin
      CanGenerateCell := True;
      Exit;
    end;
end;

function GenerateCell(var G: TGameState; X, Y: Byte; RequiredDir: TDirection): Boolean;
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
    if DrawTileFits(G, X, Y, Tile, RequiredDir, Rot) then
    begin
      if not DrawTopTile(G, Tile, False) then
        Exit;
      Rot := ChooseRotation(G, X, Y, Tile, RequiredDir, Rot);

      ClearCell(G.Board[X, Y]);
      G.Board[X, Y].Kind := Tile.Kind;
      G.Board[X, Y].Rot := Rot;
      G.Board[X, Y].Feature := Tile.Feature;
      G.Board[X, Y].Flags := [cfPresent, cfFresh];
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
  I: Byte;
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
    G.Prisoners[I].Started := False;
    G.Prisoners[I].Lit := True;
    G.Prisoners[I].HasKey := False;
    G.Prisoners[I].Falling := False;
    G.Prisoners[I].Alive := True;
    G.Prisoners[I].BonusAction := False;
    G.Prisoners[I].Nerve := StartNerve;
    G.Prisoners[I].X := 0;
    G.Prisoners[I].Y := 0;
  end;

  AddLog(G, 'Each prisoner must place a starting tile on the first turn.');
  AddLog(G, 'TAB cycles targets. ENTER confirms. I/J/K/L move after setup.');
end;

end.
