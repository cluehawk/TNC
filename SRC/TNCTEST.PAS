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
    G.Prisoners[I].Alive := False;
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
  Check(G.DrawsRemaining = 0,
    'lights-out stay still discards one draw tile');

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
  Check(G.Prisoners[0].Nerve = 2,
    'ordinary stay gains one nerve up to the maximum');
  Check(G.DrawsRemaining = 0,
    'ordinary stay discards one draw tile');
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

procedure TestFallingLanding;
var
  G: TGameState;
  Y: Byte;
begin
  ResetState(G);
  G.Prisoners[0].Alive := True;
  G.Prisoners[0].Started := True;
  G.Prisoners[0].Lit := True;
  G.Prisoners[0].Falling := True;
  G.Prisoners[0].X := 2;
  G.Prisoners[0].Y := 2;

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
  G.Prisoners[0].Falling := True;
  PutCell(G, 3, 3, tkCross, 0, ftKey, []);
  Check(LandFallingPrisoner(G, 0, 3, 3), 'prisoner lands on an existing key');
  Check(G.Prisoners[0].HasKey, 'landing prisoner collects the key');
  Check(G.Board[3, 3].Feature = ftCrumbleArmed,
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
  Check(not Eligible[2, 2], 'final flicker protects occupied tiles');
  Check(RemoveFlickerTileAt(G, 1, 1), 'selected final flicker tile is removed');
  Check(not IsPresent(G.Board[1, 1]), 'removed flicker cell becomes empty');
  Check(G.LostGates = 1, 'removed final-flicker gate is counted as lost');
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
  TestFallingLanding;
  TestUnclaimedKeyOnArmedTile;
  TestPassThenClaimStandingKey;
  TestScrambleEntryFeature;
  TestFinalFlickerSelection;

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
