program TNC;

{$G-}
{$R-}
{$S-}

uses
  Crt,
  TNCDef,
  TNCGen,
  TNCRule,
  TNCUI;

procedure AdvanceTurn(var G: TGameState);
begin
  G.ActiveIndex := (G.ActiveIndex + 1) mod PrisonerCount;
  G.ViewIndex := G.ActiveIndex;
  Inc(G.TurnNumber);
end;

procedure BuildStartTargets(const G: TGameState; var Eligible: TBoolGrid; var Count: Byte);
var
  X, Y: Byte;
begin
  FillChar(Eligible, SizeOf(Eligible), 0);
  Count := 0;
  for Y := 0 to BoardH - 1 do
    for X := 0 to BoardW - 1 do
      if not IsPresent(G.Board[X, Y]) then
      begin
        Eligible[X, Y] := True;
        Inc(Count);
      end;
end;

function ResolveStartTurn(var G: TGameState; Index: Byte): Boolean;
var
  Eligible: TBoolGrid;
  Count: Byte;
  SelX, SelY: Byte;
  Rot: Byte;
begin
  ResolveStartTurn := False;
  BuildStartTargets(G, Eligible, Count);
  if Count = 0 then
  begin
    G.Phase := gpLoss;
    AddLog(G, 'No empty board space remains for a starting tile.');
    Exit;
  end;

  DrawGame(G);
  PromptSelectBoardCell(G, Eligible, 'Choose an empty space for this start tile.', SelX, SelY);
  Rot := ChooseStartRotation(G, SelX, SelY);
  PlaceStartCell(G, SelX, SelY, Rot);
  G.Prisoners[Index].Started := True;
  G.Prisoners[Index].Lit := True;
  G.Prisoners[Index].X := SelX;
  G.Prisoners[Index].Y := SelY;
  AddLog(G, PrisonerName(Index) + ' places a start tile and kindles a small flame.');

  RebuildOccupancy(G);
  ResolveRelights(G);
  RecomputeLighting(G);
  CollapseDarkness(G);
  RebuildOccupancy(G);
  ClearFreshTiles(G);
  CheckPhaseTransitions(G);
  CheckWinLoss(G);
  ResolveStartTurn := True;
end;

procedure ResolveStayMonsterReplacement(var G: TGameState; Index: Byte);
var
  Eligible: TBoolGrid;
  Count: Byte;
  SelX, SelY: Byte;
begin
  if not G.PendingStayMonster then
    Exit;

  BuildStayMonsterTargets(G, Index, Eligible, Count);
  if Count = 0 then
  begin
    G.PendingStayMonster := False;
    AddLog(G, 'No connected tile can be replaced by the wax eater.');
    Exit;
  end;

  PromptSelectBoardCell(G, Eligible, 'Wax eater: choose a connected tile to replace.', SelX, SelY);
  PlacePendingStayMonster(G, SelX, SelY);
end;

procedure ResolveKeyPass(var G: TGameState; Index: Byte);
var
  Eligible: TBoolGrid;
  Count: Byte;
  SelX, SelY: Byte;
begin
  BuildKeyPassTargets(G, Index, Eligible, Count);
  if Count = 0 then
  begin
    AddLog(G, 'No adjacent connected prisoner can receive that key.');
    Exit;
  end;

  PromptSelectBoardCell(G, Eligible, 'Pass the key to which adjacent prisoner?', SelX, SelY);
  if not PassKeyToCell(G, Index, SelX, SelY) then
    AddLog(G, 'No key pass was completed.');
end;

procedure RefreshAfterLanding(var G: TGameState);
begin
  RebuildOccupancy(G);
  ResolveRelights(G);
  RecomputeLighting(G);
  CollapseDarkness(G);
  RebuildOccupancy(G);
  ClearFreshTiles(G);
  CheckPhaseTransitions(G);
  CheckWinLoss(G);
end;

function PopScheduledMonster(var Scheduled: TBoolGrid; var X, Y: Byte): Boolean;
var
  SX, SY: Byte;
begin
  PopScheduledMonster := False;
  for SY := 0 to BoardH - 1 do
    for SX := 0 to BoardW - 1 do
      if Scheduled[SX, SY] then
      begin
        Scheduled[SX, SY] := False;
        X := SX;
        Y := SY;
        PopScheduledMonster := True;
        Exit;
      end;
end;

procedure ResolveMonsterHits(var G: TGameState; var Scheduled: TBoolGrid);
var
  MX, MY, Victim: Byte;
  VictimMask: Byte;
  Brace: Boolean;
  Resolved: TBoolGrid;
begin
  FillChar(Resolved, SizeOf(Resolved), 0);
  while PopScheduledMonster(Scheduled, MX, MY) do
  begin
    if Resolved[MX, MY] then
      Continue;
    Resolved[MX, MY] := True;

    if (not IsPresent(G.Board[MX, MY])) or (G.Board[MX, MY].Feature <> ftMonster) then
      Continue;

    VictimMask := MonsterVictimMaskAndChains(G, MX, MY, Scheduled, Resolved);
    if VictimMask <> 0 then
    begin
      for Victim := 0 to PrisonerCount - 1 do
        if (VictimMask and (1 shl Victim)) <> 0 then
        begin
          DrawGame(G);
          if G.Prisoners[Victim].Nerve > 0 then
            Brace := PromptYesNo('Wax eater strikes ' + PrisonerName(Victim) + '. Spend nerve?')
          else
            Brace := False;
          ApplyMonsterHit(G, Victim, 1, Brace);
        end;
    end;
  end;
end;

function ResolveMonsterScramble(var G: TGameState; Index: Byte; const PromptText: string): Boolean;
var
  Cmd: Char;
  Dir: TDirection;
  MoveText: string;
  HasScramble: Boolean;
begin
  ResolveMonsterScramble := True;
  HasScramble := CanLandingScrambleDirection(G, Index, dirNorth) or
                 CanLandingScrambleDirection(G, Index, dirWest) or
                 CanLandingScrambleDirection(G, Index, dirSouth) or
                 CanLandingScrambleDirection(G, Index, dirEast);
  if not HasScramble then
  begin
    G.Phase := gpLoss;
    AddLog(G, PrisonerName(Index) + ' cannot scramble away from the wax eater.');
    ResolveMonsterScramble := False;
    Exit;
  end;

  repeat
    DrawGame(G);
    MoveText := 'Scramble:';
    if CanLandingScrambleDirection(G, Index, dirNorth) then
      MoveText := MoveText + ' I';
    if CanLandingScrambleDirection(G, Index, dirWest) then
      MoveText := MoveText + ' J';
    if CanLandingScrambleDirection(G, Index, dirSouth) then
      MoveText := MoveText + ' K';
    if CanLandingScrambleDirection(G, Index, dirEast) then
      MoveText := MoveText + ' L';
    WriteAt(3, 23, '                                                                            ');
    WriteAt(3, 24, '                                                                            ');
    WriteAt(3, 23, PromptText);
    WriteAt(3, 24, MoveText);
    GetAction(G, Cmd, Dir);
    if Cmd = 'Q' then
    begin
      G.Phase := gpLoss;
      AddLog(G, 'The player abandons the labyrinth.');
      ResolveMonsterScramble := False;
      Exit;
    end;
    if (Cmd = 'M') and ScrambleLandingPrisoner(G, Index, Dir) then
      Break;
  until False;
end;

function ResolveMonsterEscape(var G: TGameState; Index: Byte;
  const PromptText: string): Boolean;
var
  Scheduled: TBoolGrid;
begin
  ResolveMonsterEscape := False;
  while PrisonerOnMonster(G, Index) do
  begin
    if not ResolveMonsterScramble(G, Index, PromptText) then
      Exit;

    { A forced scramble still enters its destination normally.  If that
      destination is another wax eater, the new monster attacks before the
      prisoner can finish escaping. }
    if PrisonerOnMonster(G, Index) then
    begin
      BuildLandingTriggeredMonsters(G, Index, Scheduled);
      ResolveMonsterHits(G, Scheduled);
    end;
  end;
  ResolveMonsterEscape := True;
end;

function ResolveLandingMonster(var G: TGameState; Index: Byte): Boolean;
var
  Scheduled: TBoolGrid;
begin
  ResolveLandingMonster := True;
  G.PendingLandingMonster := False;
  BuildLandingTriggeredMonsters(G, Index, Scheduled);
  ResolveMonsterHits(G, Scheduled);

  if PrisonerOnMonster(G, Index) then
    if not ResolveMonsterEscape(G, Index, 'Landing hit: choose a scramble direction.') then
    begin
      ResolveLandingMonster := False;
      Exit;
    end;

  RefreshAfterLanding(G);
  if G.Phase in [gpWin, gpLoss] then
    ResolveLandingMonster := False;
end;

function ResolveFallingLanding(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
  SelX, SelY: Byte;
begin
  ResolveFallingLanding := False;
  BuildFallingTargets(G, Index, Dir, EmptyEligible, ExistingEligible, EmptyCount, ExistingCount);

  if EmptyCount > 0 then
  begin
    if G.DrawsRemaining = 0 then
      Exit;
    PromptSelectBoardCell(G, EmptyEligible, 'Choose an empty landing space on this line.', SelX, SelY)
  end
  else if ExistingCount > 0 then
    PromptSelectBoardCell(G, ExistingEligible, 'No empty space: choose an existing landing tile.', SelX, SelY)
  else
    Exit;

  if not LandFallingPrisoner(G, Index, SelX, SelY) then
    Exit;

  if not ResolveLandingMonster(G, Index) then
    Exit;

  ResolveFallingLanding := True;
end;

procedure PostActionUpdate(var G: TGameState; const BeforeMoveState, AfterMoveState: TGameState;
  Index, OldX, OldY: Byte; DidMove: Boolean);
var
  RefreshBoard: Boolean;
  Scheduled: TBoolGrid;
begin
  RefreshBoard := DidMove or G.Prisoners[Index].Falling;

  RebuildOccupancy(G);
  if DidMove or G.Prisoners[Index].Falling then
    BuildMoveTriggeredMonsters(BeforeMoveState, AfterMoveState, Index, OldX, OldY, Scheduled)
  else
    FillChar(Scheduled, SizeOf(Scheduled), 0);

  { Movement triggers the complete wax-eater chain before new passages are
    illuminated or darkness removes any queued monster. }
  ResolveMonsterHits(G, Scheduled);

  if DidMove and PrisonerOnMonster(G, Index) then
  begin
    if not ResolveMonsterEscape(G, Index, 'Monster hit: choose a scramble direction.') then
      Exit;
  end;

  RebuildOccupancy(G);
  if RefreshBoard then
  begin
    ResolveRelights(G);
    RecomputeLighting(G);
    CollapseDarkness(G);
    RebuildOccupancy(G);
  end;
  ClearFreshTiles(G);
  CheckPhaseTransitions(G);
  CheckWinLoss(G);
end;

function ResolveOneAction(var G: TGameState; Index: Byte; MoveOnly: Boolean): Boolean;
var
  Cmd: Char;
  Dir: TDirection;
  Done: Boolean;
  DidMove: Boolean;
  OldX, OldY: Byte;
  BeforeMoveState, AfterMoveState: TGameState;
begin
  ResolveOneAction := False;
  if MoveOnly and (G.Prisoners[Index].Falling or (not PrisonerHasAnyMove(G, Index))) then
  begin
    AddLog(G, 'No legal extra move remains.');
    Exit;
  end;
  if (not MoveOnly) and (not G.Prisoners[Index].Falling) and
     (not PrisonerHasAnyMove(G, Index)) and
     ((G.Prisoners[Index].Lit = False) and (G.Prisoners[Index].Nerve = 0)) then
  begin
    G.Phase := gpLoss;
    AddLog(G, PrisonerName(Index) + ' is lights out and has no legal move.');
    Exit;
  end;

  Done := False;
  DidMove := False;
  OldX := G.Prisoners[Index].X;
  OldY := G.Prisoners[Index].Y;
  BeforeMoveState := G;
  AfterMoveState := G;
  repeat
    DrawGame(G);
    if MoveOnly then
    begin
      WriteAt(3, 23, 'Extra move: I/J/K/L or arrows   P pass key   Q quit                 ');
      WriteAt(3, 24, 'Nerve grants a Move, not another Stay.                              ');
    end;
    GetAction(G, Cmd, Dir);
    case Cmd of
      'Q':
        begin
          G.Phase := gpLoss;
          AddLog(G, 'The player abandons the labyrinth.');
          Exit;
        end;
      'P':
        begin
          if G.Prisoners[Index].Falling then
            AddLog(G, 'A falling prisoner cannot pass a key.')
          else
            ResolveKeyPass(G, Index);
        end;
      'S':
        begin
          if MoveOnly then
            AddLog(G, 'Nerve grants an extra move, not another stay.')
          else if G.Prisoners[Index].Falling then
            AddLog(G, 'Choose a re-entry direction instead of staying.')
          else if StayPrisoner(G, Index) then
          begin
            ResolveStayMonsterReplacement(G, Index);
            AfterMoveState := G;
            Done := True
          end
          else
            AddLog(G, 'That prisoner cannot stay in the dark without nerve.');
        end;
      'M':
        begin
          if G.Prisoners[Index].Falling then
          begin
            if ResolveFallingLanding(G, Index, Dir) then
            begin
              OldX := G.Prisoners[Index].X;
              OldY := G.Prisoners[Index].Y;
              DidMove := False;
              { The landing, its illumination, and any landing monster have
                finished.  A subsequent normal move must compare against
                this board, not the stale pre-fall snapshot. }
              BeforeMoveState := G;
              AfterMoveState := G;
              AddLog(G, PrisonerName(Index) + ' may now take the turn normally.');
            end
            else
              AddLog(G, 'No legal landing from that edge.');
          end
          else if MoveRequiresCharge(G, Index, Dir) then
          begin
            if G.Prisoners[Index].Nerve = 0 then
              AddLog(G, 'Charging a wax eater requires 1 nerve.')
            else if PromptYesNo('Charge the wax eater and spend 1 nerve?') then
            begin
              Dec(G.Prisoners[Index].Nerve);
              AddLog(G, PrisonerName(Index) + ' charges straight into a wax eater.');
              if MovePrisoner(G, Index, Dir) then
              begin
                DidMove := True;
                AfterMoveState := G;
                Done := True;
              end
              else
                AddLog(G, 'No connected passage that way.');
            end
            else
              AddLog(G, 'The prisoner refuses to charge the wax eater.');
          end
          else if MovePrisoner(G, Index, Dir) then
          begin
            DidMove := True;
            AfterMoveState := G;
            Done := True;
          end
          else
            AddLog(G, 'No connected passage that way.');
        end;
    end;
  until Done or (G.Phase = gpLoss);

  if Done then
  begin
    PostActionUpdate(G, BeforeMoveState, AfterMoveState, Index, OldX, OldY, DidMove);
    ResolveOneAction := True;
  end;
end;

procedure ResolveFinalFlicker(var G: TGameState; Index: Byte);
var
  CancelLoss: Boolean;
  Eligible: TBoolGrid;
  Count: Byte;
  SelX, SelY: Byte;
begin
  if G.Phase <> gpFinal then
    Exit;
  if G.Phase in [gpWin, gpLoss] then
    Exit;

  BuildFlickerTargets(G, Eligible, Count);
  if Count = 0 then
  begin
    AddLog(G, 'No unoccupied illuminated tile can be removed this flicker.');
    CheckWinLoss(G);
    Exit;
  end;

  CancelLoss := False;
  DrawGame(G);
  if G.Prisoners[Index].Nerve > 0 then
    CancelLoss := PromptYesNo('Spend 1 nerve to resist this turn''s final flicker?');

  if CancelLoss and (G.Prisoners[Index].Nerve > 0) then
  begin
    Dec(G.Prisoners[Index].Nerve);
    AddLog(G, PrisonerName(Index) + ' spends 1 nerve to preserve the last glow.');
  end
  else
  begin
    PromptSelectBoardCell(G, Eligible, 'Final flicker: choose an illuminated tile to lose.', SelX, SelY);
    RemoveFlickerTileAt(G, SelX, SelY);
  end;

  RebuildOccupancy(G);
  CheckWinLoss(G);
end;

procedure GameLoop(var G: TGameState);
var
  Index: Byte;
begin
  repeat
    if G.Phase in [gpWin, gpLoss] then
      Break;

    Index := G.ActiveIndex;
    if not G.Prisoners[Index].Started then
    begin
      if not ResolveStartTurn(G, Index) then
        Break;
      if G.Phase in [gpWin, gpLoss] then
        Break;
      AdvanceTurn(G);
      Continue;
    end;
    if G.Prisoners[Index].Falling and (not HasAnyReEntry(G, Index)) then
    begin
      G.Phase := gpLoss;
      AddLog(G, PrisonerName(Index) + ' cannot find any path back into the maze.');
      Break;
    end;

    if not ResolveOneAction(G, Index, False) then
      Break;
    if G.Phase in [gpWin, gpLoss] then
      Break;

    while (G.Prisoners[Index].Nerve > 0) and
          (not G.Prisoners[Index].Falling) and
          PrisonerHasAnyMove(G, Index) do
    begin
      DrawGame(G);
      if not PromptYesNo('Spend 1 nerve to move again?') then
        Break;
      Dec(G.Prisoners[Index].Nerve);
      if not PrisonerHasAnyMove(G, Index) then
      begin
        Inc(G.Prisoners[Index].Nerve);
        AddLog(G, 'No legal move remains after reserving charge nerve.');
        Break;
      end;
      AddLog(G, PrisonerName(Index) + ' spends 1 nerve to move again.');
      if not ResolveOneAction(G, Index, True) then
        Break;
      if G.Phase in [gpWin, gpLoss] then
        Break;
    end;
    if G.Phase in [gpWin, gpLoss] then
      Break;

    ResolveFinalFlicker(G, Index);
    if G.Phase in [gpWin, gpLoss] then
      Break;

    AdvanceTurn(G);
  until False;
end;

procedure ShowEnding(const G: TGameState);
begin
  DrawGame(G);
  if G.Phase = gpWin then
    WriteAt(3, 24, 'Victory. All four prisoners reached the same gate. Press any key.')
  else
    WriteAt(3, 24, 'Game over. Eternal Darkness Reigns. Press any key.            ');
  WaitForKey;
end;

var
  Game: TGameState;

begin
  ClrScr;
  TitleScreen;
  InitGame(Game);
  Game.PromptPlacement := True;
  GameLoop(Game);
  ShowEnding(Game);
end.
