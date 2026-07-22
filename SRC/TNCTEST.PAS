program TNCTest;

{$G-}
{$R-}
{$S-}

uses
  TNCDef,
  TNCGen,
  TNCRule;

var
  Failures: Word;
  ReportFile: Text;

procedure ReportLine(S: string);
begin
  WriteLn(S);
  WriteLn(ReportFile, S);
end;

procedure Check(Condition: Boolean; MessageText: string);
begin
  if Condition then
    ReportLine('PASS: ' + MessageText)
  else
  begin
    ReportLine('FAIL: ' + MessageText);
    Inc(Failures);
  end;
end;

procedure ResetState(var G: TGameState);
var
  X, Y, I: Byte;
begin
  FillChar(G, SizeOf(G), 0);
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      ClearCell(G.Board[X, Y]);
  for I := 0 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].Alive := False;
    G.Prisoners[I].FallEdgeChosen := False;
    G.Prisoners[I].FallDir := dirNorth;
  end;
  G.Phase := gpFinal;
  G.TurnNumber := 1;
  ClearLog(G);
end;

procedure PutCell(var G: TGameState; X, Y: Byte; Kind: TTileKind;
  Rot: Byte; Feature: TFeature; Flags: TCellFlags);
begin
  ClearCell(G.Board[X, Y]);
  G.Board[X, Y].Kind := Kind;
  G.Board[X, Y].Rot := Rot;
  G.Board[X, Y].Feature := Feature;
  G.Board[X, Y].Flags := Flags + [cfPresent];
end;

procedure PrepareFinalPrisoners(var G: TGameState);
var
  I: Byte;
begin
  G.Phase := gpFinal;
  for I := 0 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].Alive := True;
    G.Prisoners[I].Started := True;
    G.Prisoners[I].Lit := True;
    G.Prisoners[I].HasKey := True;
    G.Prisoners[I].Falling := False;
    G.Prisoners[I].FallEdgeChosen := False;
    G.Prisoners[I].FallDir := dirNorth;
    G.Prisoners[I].Nerve := 0;
    G.Prisoners[I].NervePending := False;
  end;
end;

procedure TestDrawStack;
var
  G: TGameState;
begin
  InitGame(G);
  Check(G.DrawsRemaining = 76, 'solo draw stack contains 76 tiles');
  Check(G.FeatureKeys = 6, 'solo draw stack contains 6 keys');
  Check(G.FeatureGates = 4, 'solo draw stack contains 4 gates');
  Check(G.FeatureMonsters = 12, 'solo draw stack contains 12 wax eaters');
end;

procedure TestBlockingWallLighting;
var
  G: TGameState;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;

  { Straight rotation 1 opens east/west.  The start tile east of it has
    no west opening, so it is a visible blocking wall. }
  PutCell(G, 2, 2, tkStraight, 1, ftNone, []);
  PutCell(G, 3, 2, tkStart, 0, ftNone, []);
  PutCell(G, 2, 1, tkPit, 0, ftNone, []);
  RebuildOccupancy(G);
  RecomputeLighting(G);

  Check(cfLit in G.Board[2, 2].Flags, 'prisoner tile is illuminated');
  Check(cfLit in G.Board[3, 2].Flags, 'blocking wall remains illuminated');
  Check(not (cfLit in G.Board[2, 1].Flags),
    'pit behind a closed wall is not illuminated');
end;

procedure TestMultiSourceIllumination;
var
  G: TGameState;
begin
  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 1;
  G.TileStack[1].Kind := tkCorner;
  G.TileStack[1].Feature := ftNone;

  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 3;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := True;
  G.Prisoners[1].X := 1;
  G.Prisoners[1].Y := 2;

  { Both candles reveal (2,2): prisoner 0 requires its south opening and
    prisoner 1 requires its west opening.  The other openings face pits so
    there is exactly one empty illuminated space. }
  PutCell(G, 2, 3, tkStraight, 0, ftNone, []);
  PutCell(G, 2, 4, tkPit, 0, ftNone, []);
  PutCell(G, 1, 2, tkStraight, 1, ftNone, []);
  PutCell(G, 0, 2, tkPit, 0, ftNone, []);
  RebuildOccupancy(G);
  RecomputeLighting(G);

  Check(IsPresent(G.Board[2, 2]),
    'two candles generate their shared empty space once');
  Check(CellOpen(G.Board[2, 2], dirSouth) and
        CellOpen(G.Board[2, 2], dirWest),
    'shared illumination tile connects to every revealing passage');
  Check(G.DrawsRemaining = 0,
    'shared illuminated space consumes only one draw');
end;

procedure TestLightsOutDestinationOnly;
var
  G: TGameState;
begin
  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 2;
  G.TileStack[1].Kind := tkCross;
  G.TileStack[1].Feature := ftNone;
  G.TileStack[2].Kind := tkCross;
  G.TileStack[2].Feature := ftNone;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);

  Check(MovePrisoner(G, 0, dirEast),
    'lights-out prisoner can reveal and enter one destination');
  RebuildOccupancy(G);
  ResolveRelights(G);
  RecomputeLighting(G);
  CollapseDarkness(G);
  RebuildOccupancy(G);

  Check((G.Prisoners[0].X = 2) and (G.Prisoners[0].Y = 1) and
        IsPresent(G.Board[2, 1]),
    'lights-out destination remains under its prisoner');
  Check(G.DrawsRemaining = 1,
    'lights-out movement draws only its destination tile');
  Check(not IsPresent(G.Board[1, 1]),
    'unoccupied origin vanishes after lights-out movement');
  Check(not IsPresent(G.Board[2, 0]),
    'lights-out destination does not illuminate another empty space');
end;

procedure TestRelighting;
var
  G: TGameState;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 0;
  G.Prisoners[0].Y := 1;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := True;
  G.Prisoners[1].X := 2;
  G.Prisoners[1].Y := 1;
  PutCell(G, 0, 1, tkCross, 0, ftNone, []);
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(MovePrisoner(G, 0, dirEast),
    'lights-out prisoner moves beside a lit prisoner');
  ResolveRelights(G);
  Check(G.Prisoners[0].Lit,
    'moving lights-out prisoner is relit by adjacency');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 1;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := True;
  G.Prisoners[1].X := 0;
  G.Prisoners[1].Y := 1;
  PutCell(G, 0, 1, tkCross, 0, ftNone, []);
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(MovePrisoner(G, 1, dirEast),
    'lit prisoner moves beside a lights-out prisoner');
  ResolveRelights(G);
  Check(G.Prisoners[0].Lit,
    'stationary lights-out prisoner is relit by the arriving flame');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 0;
  G.Prisoners[0].Y := 1;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := False;
  G.Prisoners[1].X := 1;
  G.Prisoners[1].Y := 1;
  G.Prisoners[2].Alive := True;
  G.Prisoners[2].Started := True;
  G.Prisoners[2].Lit := True;
  G.Prisoners[2].X := 2;
  G.Prisoners[2].Y := 1;
  PutCell(G, 0, 1, tkCross, 0, ftNone, []);
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  ResolveRelights(G);
  Check(G.Prisoners[0].Lit and G.Prisoners[1].Lit,
    'newly relit candle relays flame regardless of prisoner order');
end;

procedure TestRelitCandleExpansion;
var
  G: TGameState;
begin
  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 1;
  G.TileStack[1].Kind := tkCross;
  G.TileStack[1].Feature := ftNone;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := True;
  G.Prisoners[1].X := 2;
  G.Prisoners[1].Y := 1;
  PutCell(G, 1, 1, tkCorner, 0, ftNone, []);
  PutCell(G, 2, 1, tkCorner, 2, ftNone, []);
  PutCell(G, 2, 2, tkPit, 0, ftNone, []);
  RebuildOccupancy(G);

  ResolveRelights(G);
  RecomputeLighting(G);
  Check(G.Prisoners[0].Lit,
    'adjacent connected candle is relit before illumination');
  Check(IsPresent(G.Board[1, 0]),
    'newly relit candle immediately reveals its full radius');
  Check(G.DrawsRemaining = 0,
    'newly relit candle expansion consumes the expected draw');
end;

procedure TestStayNerveRules;
var
  G: TGameState;
begin
  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 1;
  G.TileStack[1].Kind := tkCross;
  G.TileStack[1].Feature := ftNone;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].Nerve := 1;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  Check(StayPrisoner(G, 0),
    'lights-out prisoner may spend nerve to stay');
  Check(G.Prisoners[0].Nerve = 0,
    'lights-out stay costs one nerve without gaining it back');
  Check(not G.Prisoners[0].NervePending,
    'lights-out stay does not schedule a nerve gain');
  Check(G.DrawsRemaining = 0,
    'lights-out stay still discards one draw tile');
  ApplyPendingNerve(G, 0);
  Check(G.Prisoners[0].Nerve = 0,
    'turn end does not refund a lights-out stay');

  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 1;
  G.TileStack[1].Kind := tkCross;
  G.TileStack[1].Feature := ftNone;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].Nerve := 1;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  Check(StayPrisoner(G, 0), 'lit prisoner may stay normally');
  Check((G.Prisoners[0].Nerve = 1) and G.Prisoners[0].NervePending,
    'stay-earned nerve is unavailable during the current turn');
  Check(G.DrawsRemaining = 0,
    'ordinary stay discards one draw tile');
  ApplyPendingNerve(G, 0);
  Check((G.Prisoners[0].Nerve = 2) and
        (not G.Prisoners[0].NervePending),
    'ordinary stay awards nerve only at turn end');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].Nerve := MaxNerve;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  Check(StayPrisoner(G, 0),
    'full-nerve prisoner may earn a deferred stay nerve');
  Dec(G.Prisoners[0].Nerve);
  ApplyPendingNerve(G, 0);
  Check(G.Prisoners[0].Nerve = MaxNerve,
    'deferred stay nerve replenishes nerve spent before turn end');
end;

procedure TestMonsterChainResolution;
var
  G: TGameState;
  Scheduled, Resolved: TBoolGrid;
  Victims: Byte;
begin
  ResetState(G);
  PutCell(G, 1, 1, tkCross, 0, ftMonster, []);
  PutCell(G, 2, 1, tkCross, 0, ftMonster, []);
  FillChar(Scheduled, SizeOf(Scheduled), 0);
  FillChar(Resolved, SizeOf(Resolved), 0);

  Resolved[1, 1] := True;
  Victims := MonsterVictimMaskAndChains(G, 1, 1, Scheduled, Resolved);
  Check(Scheduled[2, 1], 'first wax eater schedules the second');
  Check(Victims = 0, 'empty monster chain has no prisoner victims');

  Scheduled[2, 1] := False;
  Resolved[2, 1] := True;
  Victims := MonsterVictimMaskAndChains(G, 2, 1, Scheduled, Resolved);
  Check(not Scheduled[1, 1], 'resolved wax eater is not queued again');
  Check(Victims = 0, 'return chain still has no prisoner victims');

  PutCell(G, 3, 3, tkStraight, 1, ftGate, []);
  G.PendingStayMonster := True;
  PlacePendingStayMonster(G, 3, 3);
  Check(G.Board[3, 3].Kind = tkCross,
    'staying wax eater replaces the complete tile topology');
  Check(G.Board[3, 3].Feature = ftMonster,
    'staying replacement places a wax eater feature');
  Check(G.LostGates = 1, 'gate replaced by a staying wax eater is counted lost');
end;

procedure TestMonsterTriggerGeometry;
var
  G, BeforeG, AfterG: TGameState;
  Scheduled, Resolved: TBoolGrid;
  Victims: Byte;
begin
  { Moving along a wax eater's corridor triggers it and leaves the moving
    prisoner in the resolved line of attack. }
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  PutCell(G, 0, 2, tkCross, 0, ftMonster, []);
  PutCell(G, 1, 2, tkCross, 0, ftNone, []);
  PutCell(G, 2, 2, tkCross, 0, ftNone, []);
  PutCell(G, 3, 2, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  BeforeG := G;
  Check(MovePrisoner(G, 0, dirEast),
    'prisoner moves along a wax eater corridor');
  AfterG := G;
  BuildMoveTriggeredMonsters(BeforeG, AfterG, 0, 2, 2, Scheduled);
  Check(Scheduled[0, 2],
    'moving along a wax eater corridor triggers the monster');
  Scheduled[0, 2] := False;
  FillChar(Resolved, SizeOf(Resolved), 0);
  Resolved[0, 2] := True;
  Victims := MonsterVictimMaskAndChains(AfterG, 0, 2, Scheduled, Resolved);
  Check((Victims and 1) <> 0,
    'prisoner remaining in the corridor is hit');

  { Entering a visible corridor from the side also triggers the monster. }
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 1;
  PutCell(G, 0, 2, tkCross, 0, ftMonster, []);
  PutCell(G, 1, 2, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 2, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  BeforeG := G;
  Check(MovePrisoner(G, 0, dirSouth),
    'prisoner moves into a wax eater corridor');
  AfterG := G;
  BuildMoveTriggeredMonsters(BeforeG, AfterG, 0, 2, 1, Scheduled);
  Check(Scheduled[0, 2],
    'moving into a wax eater corridor triggers the monster');
  Scheduled[0, 2] := False;
  FillChar(Resolved, SizeOf(Resolved), 0);
  Resolved[0, 2] := True;
  Victims := MonsterVictimMaskAndChains(AfterG, 0, 2, Scheduled, Resolved);
  Check((Victims and 1) <> 0,
    'prisoner entering the corridor is hit');

  { Leaving the line still triggers the monster, but the attack uses current
    positions.  The mover escapes while another prisoner in line is hit. }
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := True;
  G.Prisoners[1].X := 3;
  G.Prisoners[1].Y := 2;
  PutCell(G, 0, 2, tkCross, 0, ftMonster, []);
  PutCell(G, 1, 2, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 2, tkCross, 0, ftNone, []);
  PutCell(G, 3, 2, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  BeforeG := G;
  Check(MovePrisoner(G, 0, dirNorth),
    'prisoner moves sideways out of a wax eater corridor');
  AfterG := G;
  BuildMoveTriggeredMonsters(BeforeG, AfterG, 0, 2, 2, Scheduled);
  Check(Scheduled[0, 2],
    'moving out of a wax eater corridor still triggers the monster');
  Scheduled[0, 2] := False;
  FillChar(Resolved, SizeOf(Resolved), 0);
  Resolved[0, 2] := True;
  Victims := MonsterVictimMaskAndChains(AfterG, 0, 2, Scheduled, Resolved);
  Check(((Victims and 1) = 0) and ((Victims and 2) <> 0),
    'side-step evades the hit while a prisoner still in line is struck');

  { Wax eater sight follows the toroidal board edge. }
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 4;
  G.Prisoners[0].Y := 0;
  PutCell(G, 0, 0, tkCross, 0, ftMonster, []);
  PutCell(G, 4, 0, tkCross, 0, ftNone, []);
  PutCell(G, 5, 0, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  BeforeG := G;
  Check(MovePrisoner(G, 0, dirEast),
    'prisoner moves in a corridor crossing the board edge');
  AfterG := G;
  BuildMoveTriggeredMonsters(BeforeG, AfterG, 0, 4, 0, Scheduled);
  Check(Scheduled[0, 0],
    'wax eater line of sight triggers across the wrapped edge');
  Scheduled[0, 0] := False;
  FillChar(Resolved, SizeOf(Resolved), 0);
  Resolved[0, 0] := True;
  Victims := MonsterVictimMaskAndChains(AfterG, 0, 0, Scheduled, Resolved);
  Check((Victims and 1) <> 0,
    'wrapped wax eater attack hits the prisoner');

  { Gaps, walls, and pits each stop the attack trace. }
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  PutCell(G, 0, 2, tkCross, 0, ftMonster, []);
  PutCell(G, 2, 2, tkCross, 0, ftNone, []);
  FillChar(Scheduled, SizeOf(Scheduled), 0);
  FillChar(Resolved, SizeOf(Resolved), 0);
  Resolved[0, 2] := True;
  Victims := MonsterVictimMaskAndChains(G, 0, 2, Scheduled, Resolved);
  Check(Victims = 0, 'an empty gap blocks a wax eater attack');

  PutCell(G, 1, 2, tkStraight, 0, ftNone, []);
  FillChar(Scheduled, SizeOf(Scheduled), 0);
  Victims := MonsterVictimMaskAndChains(G, 0, 2, Scheduled, Resolved);
  Check(Victims = 0, 'a disconnected wall blocks a wax eater attack');

  PutCell(G, 1, 2, tkPit, 0, ftNone, []);
  FillChar(Scheduled, SizeOf(Scheduled), 0);
  Victims := MonsterVictimMaskAndChains(G, 0, 2, Scheduled, Resolved);
  Check(Victims = 0, 'a pit blocks a wax eater attack');

  { Moving from a crumbling tile forms a pit after the monster is triggered.
    The new pit then shields the prisoner from the resolved attack. }
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  PutCell(G, 0, 2, tkCross, 0, ftMonster, []);
  PutCell(G, 1, 2, tkCross, 0, ftNone, []);
  PutCell(G, 2, 2, tkStraight, 1, ftCrumbleArmed, []);
  PutCell(G, 3, 2, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  BeforeG := G;
  Check(MovePrisoner(G, 0, dirEast),
    'prisoner escapes a wax eater line from crumbling stone');
  AfterG := G;
  Check(AfterG.Board[2, 2].Kind = tkPit,
    'movement leaves a pit in the former attack corridor');
  BuildMoveTriggeredMonsters(BeforeG, AfterG, 0, 2, 2, Scheduled);
  Check(Scheduled[0, 2],
    'wax eater is triggered from the pre-collapse corridor');
  Scheduled[0, 2] := False;
  FillChar(Resolved, SizeOf(Resolved), 0);
  Resolved[0, 2] := True;
  Victims := MonsterVictimMaskAndChains(AfterG, 0, 2, Scheduled, Resolved);
  Check((Victims and 1) = 0,
    'new pit blocks the resolved attack and protects the mover');
end;

procedure TestMonsterHitPenalties;
var
  G: TGameState;
begin
  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 10;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].Nerve := 1;
  ApplyMonsterHit(G, 0, 1, False);
  Check((G.DrawsRemaining = 7) and (not G.Prisoners[0].Lit),
    'unblocked wax eater hit discards three tiles and causes lights out');
  Check(G.Prisoners[0].Nerve = 1,
    'unblocked wax eater hit does not spend nerve');

  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 10;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].Nerve := 1;
  ApplyMonsterHit(G, 0, 1, True);
  Check((G.DrawsRemaining = 8) and (not G.Prisoners[0].Lit),
    'blocking with nerve reduces a wax eater hit to two tiles');
  Check(G.Prisoners[0].Nerve = 0,
    'blocking a wax eater hit spends one nerve');

  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 10;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  ApplyMonsterHit(G, 0, 1, False);
  ApplyMonsterHit(G, 0, 1, False);
  Check(G.DrawsRemaining = 4,
    'two wax eater hits each discard their full three-tile penalty');

  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 2;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  ApplyMonsterHit(G, 0, 1, False);
  Check(G.DrawsRemaining = 0,
    'wax eater penalty discards every remaining tile without underflow');
  CheckPhaseTransitions(G);
  Check(G.Phase = gpFinal,
    'exhausting the stack during an attack begins Final Flickers');
end;

procedure TestMonsterAftermath;
var
  G: TGameState;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftMonster, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(ScrambleLandingPrisoner(G, 0, dirEast),
    'ordinary lights-out monster encounter allows a scramble');
  Check(G.Board[1, 1].Feature = ftMonster,
    'ordinary lights-out encounter leaves the wax eater in place');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftMonster, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(ScrambleFromMonster(G, 0, dirEast, True, 1, 1),
    'falling prisoner scrambles away from a landed-on wax eater');
  Check(not IsPresent(G.Board[1, 1]),
    'landed-on wax eater is discarded after the scramble');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftMonster, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(ConvertMonsterToPit(G, 1, 1),
    'charged wax eater converts into a pit after attacking');
  Check(PrisonerOnPit(G, 0),
    'charger remains over the new pit until choosing fall or scramble');
  Check(ScrambleFromMonster(G, 0, dirEast, False, 1, 1),
    'charger may scramble from the resulting pit');
  Check(IsPresent(G.Board[1, 1]) and (G.Board[1, 1].Kind = tkPit) and
        (G.Board[1, 1].Feature = ftNone),
    'charged wax eater pit remains after the prisoner scrambles');
end;

procedure TestCrumbleAndPitLifecycle;
var
  G: TGameState;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkStraight, 1, ftCrumbleFresh, []);
  PutCell(G, 3, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(MovePrisoner(G, 0, dirEast),
    'prisoner enters a fresh crumbling passage');
  Check(G.Board[2, 1].Feature = ftCrumbleArmed,
    'entering a crumbling passage arms it for collapse');
  Check(PrisonerOnBreakableTile(G, 0),
    'armed crumbling passage is reported beneath the prisoner');
  RebuildOccupancy(G);
  Check(MovePrisoner(G, 0, dirEast),
    'prisoner moves away from an armed crumbling passage');
  Check((G.Board[2, 1].Kind = tkPit) and
        (G.Board[2, 1].Feature = ftNone),
    'leaving an armed crumbling passage turns it into a pit');
  Check(not G.Prisoners[0].Falling,
    'moving safely away from a crumble does not make the prisoner fall');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkStart, 0, ftNone, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(MovePrisoner(G, 0, dirEast),
    'prisoner leaves a starting tile through its open passage');
  Check(G.Board[1, 1].Kind = tkPit,
    'starting tile collapses into a pit when left');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].Nerve := 0;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  PutCell(G, 2, 2, tkTJunction, 1, ftCrumbleArmed, []);
  RebuildOccupancy(G);
  Check(StayPrisoner(G, 0),
    'prisoner may stay on an armed crumbling tile');
  Check((G.Board[2, 2].Kind = tkPit) and G.Prisoners[0].Falling,
    'staying collapses the tile and begins a fall');
  Check(not G.Prisoners[0].FallEdgeChosen,
    'new fall waits for its immediate edge choice');
  Check(G.Prisoners[0].NervePending,
    'a lit stay still earns nerve when the tile collapses');
  Check(ChooseFallEdge(G, 0, dirWest) and
        G.Prisoners[0].FallEdgeChosen and
        (G.Prisoners[0].FallDir = dirWest),
    'fall edge is recorded when the fall begins');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].HasKey := True;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkPit, 0, ftNone, []);
  RebuildOccupancy(G);
  Check(CanMoveDirection(G, 0, dirEast),
    'an open passage permits an intentional leap into an adjacent pit');
  Check(MovePrisoner(G, 0, dirEast),
    'prisoner deliberately moves into the pit');
  Check(G.Prisoners[0].Falling and
        (G.Prisoners[0].X = 2) and (G.Prisoners[0].Y = 1),
    'pit entry immediately places the prisoner in the falling state');
  Check(not PrisonerHasAnyMove(G, 0),
    'falling prisoner cannot take another movement action');
end;

procedure TestFallingLightAndMonsterTrigger;
var
  G, BeforeG, AfterG: TGameState;
  Scheduled, Resolved: TBoolGrid;
  Victims: Byte;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  PutCell(G, 2, 2, tkStart, 0, ftNone, [cfLit]);
  PutCell(G, 2, 1, tkCross, 0, ftNone, [cfLit]);
  PutCell(G, 3, 2, tkCross, 0, ftNone, [cfLit]);
  RebuildOccupancy(G);
  Check(StayPrisoner(G, 0),
    'staying on a starting tile begins a candlelit fall');
  ChooseFallEdge(G, 0, dirNorth);
  RebuildOccupancy(G);
  RecomputeLighting(G);
  CollapseDarkness(G);
  Check((not IsPresent(G.Board[2, 2])) and
        (not IsPresent(G.Board[2, 1])) and
        (not IsPresent(G.Board[3, 2])),
    'falling candle no longer preserves its former illuminated tiles');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := True;
  G.Prisoners[1].X := 1;
  G.Prisoners[1].Y := 2;
  PutCell(G, 0, 2, tkCross, 0, ftMonster, []);
  PutCell(G, 1, 2, tkCross, 0, ftNone, []);
  PutCell(G, 2, 2, tkTJunction, 1, ftCrumbleArmed, []);
  RebuildOccupancy(G);
  BeforeG := G;
  Check(StayPrisoner(G, 0),
    'staying prisoner falls through a crumble in monster sight');
  AfterG := G;
  BuildMoveTriggeredMonsters(BeforeG, AfterG, 0, 2, 2, Scheduled);
  Check(Scheduled[0, 2],
    'falling through a crumble triggers a watching wax eater');
  Scheduled[0, 2] := False;
  FillChar(Resolved, SizeOf(Resolved), 0);
  Resolved[0, 2] := True;
  Victims := MonsterVictimMaskAndChains(AfterG, 0, 2, Scheduled, Resolved);
  Check(((Victims and 1) = 0) and ((Victims and 2) <> 0),
    'falling prisoner evades while another prisoner in the attack line is hit');
end;

procedure TestLockedFallingEntry;
var
  G: TGameState;
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 3;
  BeginPrisonerFall(G, 0);
  ChooseFallEdge(G, 0, dirNorth);
  BuildFallingTargets(G, 0, dirNorth, EmptyEligible, ExistingEligible,
    EmptyCount, ExistingCount);
  Check(EmptyCount = BoardH,
    'chosen north edge exposes only the original column for landing');
  BuildFallingTargets(G, 0, dirWest, EmptyEligible, ExistingEligible,
    EmptyCount, ExistingCount);
  Check((EmptyCount = 0) and (ExistingCount = 0),
    'a different row or column cannot be chosen on the next turn');

  PutCell(G, 2, 1, tkCross, 0, ftKey, []);
  Check(not LandFallingPrisoner(G, 0, 2, 1),
    'existing tile cannot be selected while the locked line has empty spaces');

  ResetState(G);
  G.Phase := gpMaze;
  G.DrawsRemaining := 1;
  G.TileStack[1].Kind := tkCross;
  G.TileStack[1].Feature := ftKey;
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  BeginPrisonerFall(G, 0);
  ChooseFallEdge(G, 0, dirNorth);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  Check(not ResolveFallingEntry(G, 0, dirWest),
    're-entry rejects an edge different from the stored fall edge');
  Check(ResolveFallingEntry(G, 0, dirNorth),
    'prisoner draws a landing tile on the stored column');
  Check((not G.Prisoners[0].Falling) and
        (not G.Prisoners[0].FallEdgeChosen) and
        G.Prisoners[0].HasKey,
    'landing clears fall state and resolves the landing tile feature');
  RebuildOccupancy(G);
  Check(MovePrisoner(G, 0, dirSouth),
    'landed prisoner can immediately take the normal turn');
  Check(G.Board[2, 0].Kind = tkPit,
    'moving normally after landing collapses the landed-on key tile');
end;

procedure TestLockedFallReachability;
var
  G: TGameState;

  procedure PrepareScenario(var S: TGameState; Edge: TDirection);
  var
    I, Y: Byte;
  begin
    ResetState(S);
    PrepareFinalPrisoners(S);
    S.Prisoners[0].X := 0;
    S.Prisoners[0].Y := 0;
    BeginPrisonerFall(S, 0);
    ChooseFallEdge(S, 0, Edge);
    for I := 1 to PrisonerCount - 1 do
    begin
      S.Prisoners[I].X := 3;
      S.Prisoners[I].Y := 3;
    end;

    PutCell(S, 0, 0, tkPit, 0, ftNone, []);
    for Y := 1 to BoardH - 1 do
      PutCell(S, 0, Y, tkStraight, 1, ftNone, []);
    PutCell(S, 1, 0, tkStraight, 1, ftNone, []);
    PutCell(S, 2, 0, tkStraight, 1, ftNone, []);
    PutCell(S, 3, 0, tkCorner, 2, ftNone, []);
    PutCell(S, 4, 0, tkPit, 0, ftNone, []);
    PutCell(S, 5, 0, tkPit, 0, ftNone, []);
    PutCell(S, 3, 1, tkStraight, 0, ftNone, []);
    PutCell(S, 3, 2, tkStraight, 0, ftNone, []);
    PutCell(S, 3, 3, tkCross, 0, ftGate, []);
    RebuildOccupancy(S);
  end;

begin
  PrepareScenario(G, dirNorth);
  CheckWinLoss(G);
  Check(G.Phase = gpLoss,
    'Final Flickers rejects a gate reachable only from the unchosen fall row');

  PrepareScenario(G, dirEast);
  CheckWinLoss(G);
  Check(G.Phase = gpFinal,
    'Final Flickers accepts the gate when the stored fall row reaches it');
end;

procedure TestFallingLanding;
var
  G: TGameState;
  Y: Byte;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;
  BeginPrisonerFall(G, 0);
  Check(ChooseFallEdge(G, 0, dirNorth),
    'falling prisoner locks an edge before re-entry');

  PutCell(G, 2, 0, tkCross, 0, ftNone, []);
  Check(not CanReEnterDirection(G, 0, dirNorth),
    'falling prisoner cannot bypass empty spaces with an exhausted stack');

  for Y := 0 to BoardH - 1 do
    PutCell(G, 2, Y, tkCross, 0, ftNone, []);
  Check(CanReEnterDirection(G, 0, dirNorth),
    'falling prisoner may use an existing tile when no empty space remains');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].X := 3;
  G.Prisoners[0].Y := 3;
  BeginPrisonerFall(G, 0);
  ChooseFallEdge(G, 0, dirNorth);
  G.Phase := gpMaze;
  G.DrawsRemaining := 1;
  G.TileStack[1].Kind := tkCross;
  G.TileStack[1].Feature := ftKey;
  Check(LandFallingPrisoner(G, 0, 3, 0), 'prisoner draws and lands on a key');
  Check(G.Prisoners[0].HasKey, 'landing prisoner collects the key');
  Check(G.Board[3, 0].Feature = ftCrumbleArmed,
    'landed-on key tile becomes armed crumble');
end;

procedure TestUnclaimedKeyOnArmedTile;
var
  G: TGameState;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].HasKey := True;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftNone, []);
  PutCell(G, 2, 1, tkCross, 0, ftKey, []);
  PutCell(G, 3, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);

  Check(MovePrisoner(G, 0, dirEast),
    'keyed prisoner may enter another key tile');
  Check(G.Prisoners[0].HasKey,
    'entering a second key tile keeps the held key');
  Check(G.Board[2, 1].Feature = ftKeyArmed,
    'unclaimed key remains on its armed crumbling tile');
  Check(RemainingKeys(G) = 2,
    'armed unclaimed key remains part of escape capacity');

  RebuildOccupancy(G);
  Check(MovePrisoner(G, 0, dirEast),
    'keyed prisoner may leave the armed key tile');
  Check(G.Board[2, 1].Kind = tkPit,
    'armed key tile collapses when the prisoner leaves');
  Check(G.LostKeys = 1,
    'unclaimed key is counted lost when its tile collapses');
end;

procedure TestPassThenClaimStandingKey;
var
  G: TGameState;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].HasKey := True;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  G.Prisoners[1].Alive := True;
  G.Prisoners[1].Started := True;
  G.Prisoners[1].Lit := True;
  G.Prisoners[1].X := 2;
  G.Prisoners[1].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftKeyArmed, []);
  PutCell(G, 2, 1, tkCross, 0, ftNone, []);
  RebuildOccupancy(G);

  Check(PassKeyToCell(G, 0, 2, 1),
    'held key passes to an adjacent connected prisoner');
  Check(G.Prisoners[0].HasKey and G.Prisoners[1].HasKey,
    'freed hand immediately claims the key under the giver');
  Check(G.Board[1, 1].Feature = ftCrumbleArmed,
    'claimed standing key leaves an armed crumble tile');
end;

procedure TestScrambleEntryFeature;
var
  G: TGameState;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := False;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftMonster, []);
  PutCell(G, 2, 1, tkCross, 0, ftKey, []);
  RebuildOccupancy(G);

  Check(ScrambleLandingPrisoner(G, 0, dirEast),
    'monster-hit prisoner scrambles onto an adjacent key');
  Check(G.Prisoners[0].HasKey,
    'forced scramble resolves key pickup');
  Check(G.Board[2, 1].Feature = ftCrumbleArmed,
    'forced scramble arms the entered key tile');

  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].X := 1;
  G.Prisoners[0].Y := 1;
  PutCell(G, 1, 1, tkCross, 0, ftMonster, []);
  PutCell(G, 1, 2, tkTJunction, 0, ftCrumbleFresh, []);
  RebuildOccupancy(G);
  Check(ScrambleLandingPrisoner(G, 0, dirSouth),
    'monster-hit prisoner scrambles onto a crumble tile');
  Check(G.Board[1, 2].Feature = ftCrumbleArmed,
    'forced scramble arms an entered crumble tile');
end;

procedure TestFinalFlickerSelection;
var
  G: TGameState;
  Eligible: TBoolGrid;
  Count: Byte;
begin
  ResetState(G);
  PutCell(G, 1, 1, tkCross, 0, ftGate, [cfLit]);
  PutCell(G, 2, 2, tkCross, 0, ftNone, [cfLit, cfOccupied]);
  BuildFlickerTargets(G, Eligible, Count);
  Check((Count = 1) and Eligible[1, 1],
    'final flicker offers each removable illuminated tile');
  Check(not Eligible[2, 2],
    'final flicker protects occupied tiles while another choice exists');
  Check(not RemoveFlickerTileAt(G, 2, 2),
    'occupied flicker target is rejected while another choice exists');
  Check(RemoveFlickerTileAt(G, 1, 1), 'selected final flicker tile is removed');
  Check(not IsPresent(G.Board[1, 1]), 'removed flicker cell becomes empty');
  Check(G.LostGates = 1, 'removed final-flicker gate is counted as lost');

  ResetState(G);
  PutCell(G, 2, 2, tkCross, 0, ftNone, [cfLit, cfOccupied]);
  BuildFlickerTargets(G, Eligible, Count);
  Check((Count = 1) and Eligible[2, 2],
    'occupied illuminated tile becomes the last-resort flicker target');
  Check(RemoveFlickerTileAt(G, 2, 2),
    'last-resort occupied flicker tile is removed');
  Check((G.Phase = gpLoss) and (not IsPresent(G.Board[2, 2])),
    'removing a prisoner tile in Final Flickers loses the game');
end;

procedure TestFinalIsolationLoss;
var
  G: TGameState;
  I, X: Byte;
begin
  ResetState(G);
  PrepareFinalPrisoners(G);
  for I := 0 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].X := I;
    G.Prisoners[I].Y := 1;
  end;
  for X := 0 to 3 do
    PutCell(G, X, 1, tkStraight, 1, ftNone, []);
  PutCell(G, 4, 1, tkCross, 0, ftGate, []);
  RebuildOccupancy(G);
  CheckWinLoss(G);
  Check(G.Phase = gpFinal,
    'connected prisoners remain alive when one common gate is reachable');

  ResetState(G);
  PrepareFinalPrisoners(G);
  G.Prisoners[0].X := 0;
  G.Prisoners[0].Y := 0;
  for I := 1 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].X := 3;
    G.Prisoners[I].Y := 3;
  end;
  PutCell(G, 0, 0, tkCross, 0, ftNone, []);
  PutCell(G, 3, 3, tkCross, 0, ftGate, []);
  RebuildOccupancy(G);
  CheckWinLoss(G);
  Check(G.Phase = gpLoss,
    'Final Flickers loses when no gate is reachable by every prisoner');

  ResetState(G);
  PrepareFinalPrisoners(G);
  G.Prisoners[0].HasKey := False;
  for I := 0 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].X := I;
    G.Prisoners[I].Y := 1;
  end;
  for X := 0 to 3 do
    PutCell(G, X, 1, tkStraight, 1, ftNone, []);
  PutCell(G, 4, 1, tkCross, 0, ftGate, []);
  PutCell(G, 0, 4, tkCross, 0, ftKey, []);
  RebuildOccupancy(G);
  Check(RemainingKeys(G) = 4,
    'raw key count includes an isolated board key');
  CheckWinLoss(G);
  Check(G.Phase = gpLoss,
    'Final Flickers loses when a required key is unreachable');

  ResetState(G);
  PrepareFinalPrisoners(G);
  G.Prisoners[0].X := 0;
  G.Prisoners[0].Y := 0;
  for I := 1 to PrisonerCount - 1 do
  begin
    G.Prisoners[I].X := 5;
    G.Prisoners[I].Y := 0;
  end;
  PutCell(G, 0, 0, tkStart, 0, ftNone, []);
  for X := 1 to 4 do
    PutCell(G, X, 0, tkPit, 0, ftNone, []);
  PutCell(G, 5, 0, tkCross, 0, ftGate, []);
  RebuildOccupancy(G);
  CheckWinLoss(G);
  Check(G.Phase = gpFinal,
    'full-row falling route prevents a false isolation loss');
end;

var
  ResultCode: Byte;
  FailureText: string;

begin
  Assign(ReportFile, 'TNCTEST.OUT');
  Rewrite(ReportFile);
  Failures := 0;
  ReportLine('THE NIGHT CAGE CORE RULE REGRESSION TESTS');
  TestDrawStack;
  TestBlockingWallLighting;
  TestMultiSourceIllumination;
  TestLightsOutDestinationOnly;
  TestRelighting;
  TestRelitCandleExpansion;
  TestStayNerveRules;
  TestMonsterChainResolution;
  TestMonsterTriggerGeometry;
  TestMonsterHitPenalties;
  TestMonsterAftermath;
  TestCrumbleAndPitLifecycle;
  TestFallingLightAndMonsterTrigger;
  TestLockedFallingEntry;
  TestLockedFallReachability;
  TestFallingLanding;
  TestUnclaimedKeyOnArmedTile;
  TestPassThenClaimStandingKey;
  TestScrambleEntryFeature;
  TestFinalFlickerSelection;
  TestFinalIsolationLoss;

  if Failures = 0 then
  begin
    ReportLine('ALL TESTS PASSED');
    ResultCode := 0;
  end
  else
  begin
    Str(Failures, FailureText);
    ReportLine(FailureText + ' TEST(S) FAILED');
    ResultCode := 1;
  end;
  Close(ReportFile);
  Halt(ResultCode);
end.
