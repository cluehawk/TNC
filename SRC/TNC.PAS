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

procedure RefreshAfterLanding(var G: TGameState);
begin
  RebuildOccupancy(G);
  ResolveRelights(G);
  RecomputeLighting(G);
  CollapseDarkness(G);
  RebuildOccupancy(G);
  CheckPhaseTransitions(G);
  CheckWinLoss(G);
end;

function HitCountTotal(const HitCounts: TPrisonerHitCounts): Byte;
var
  I, Total: Byte;
begin
  Total := 0;
  for I := 0 to PrisonerCount - 1 do
    Inc(Total, HitCounts[I]);
  HitCountTotal := Total;
end;

procedure ResolveMonsterHits(var G: TGameState; const HitCounts: TPrisonerHitCounts);
var
  Victim, HitIndex: Byte;
  Brace: Boolean;
begin
  for Victim := 0 to PrisonerCount - 1 do
    for HitIndex := 1 to HitCounts[Victim] do
    begin
      DrawGame(G);
      if G.Prisoners[Victim].Nerve > 0 then
        Brace := PromptYesNo('Wax eater strikes ' + PrisonerName(Victim) + '. Spend nerve?')
      else
        Brace := False;
      ApplyMonsterHit(G, Victim, 1, Brace);
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
    if (Cmd = 'M') and ScrambleLandingPrisoner(G, Index, Dir) then
      Break;
  until False;
end;

function ResolveLandingMonster(var G: TGameState; Index: Byte): Boolean;
var
  HitCounts: TPrisonerHitCounts;
begin
  ResolveLandingMonster := True;
  G.PendingLandingMonster := False;
  BuildLandingMonsterHits(G, Index, HitCounts);
  if HitCountTotal(HitCounts) > 0 then
    ResolveMonsterHits(G, HitCounts);

  if PrisonerOnMonster(G, Index) then
    if not ResolveMonsterScramble(G, Index, 'Landing hit: choose a scramble direction.') then
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

  if (EmptyCount > 0) and (G.DrawsRemaining > 0) then
    PromptSelectBoardCell(G, EmptyEligible, 'Choose an empty landing space on this line.', SelX, SelY)
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

procedure PostActionUpdate(var G: TGameState; Index, OldX, OldY: Byte; DidMove: Boolean);
var
  HitCounts: TPrisonerHitCounts;
  RefreshBoard: Boolean;
begin
  RefreshBoard := DidMove or G.Prisoners[Index].Falling;

  RebuildOccupancy(G);
  if RefreshBoard then
  begin
    ResolveRelights(G);
    RecomputeLighting(G);
  end;

  if DidMove then
    BuildMoveMonsterHits(G, Index, OldX, OldY, HitCounts)
  else
    FillChar(HitCounts, SizeOf(HitCounts), 0);

  if HitCountTotal(HitCounts) > 0 then
  begin
    ResolveMonsterHits(G, HitCounts);
    if RefreshBoard then
    begin
      ResolveRelights(G);
      RebuildOccupancy(G);
      RecomputeLighting(G);
    end;
  end;

  if DidMove and PrisonerOnMonster(G, Index) then
  begin
    if not ResolveMonsterScramble(G, Index, 'Monster hit: choose a scramble direction.') then
      Exit;
    RebuildOccupancy(G);
    ResolveRelights(G);
    RecomputeLighting(G);
  end;

  RebuildOccupancy(G);
  if RefreshBoard then
  begin
    CollapseDarkness(G);
    RebuildOccupancy(G);
  end;
  CheckPhaseTransitions(G);
  CheckWinLoss(G);
end;

function ResolveOneAction(var G: TGameState; Index: Byte): Boolean;
var
  Cmd: Char;
  Dir: TDirection;
  Done: Boolean;
  DidMove: Boolean;
  OldX, OldY: Byte;
begin
  ResolveOneAction := False;
  Done := False;
  DidMove := False;
  OldX := G.Prisoners[Index].X;
  OldY := G.Prisoners[Index].Y;
  repeat
    DrawGame(G);
    GetAction(G, Cmd, Dir);
    case Cmd of
      'Q':
        begin
          G.Phase := gpLoss;
          AddLog(G, 'The player abandons the labyrinth.');
          Exit;
        end;
      'N':
        begin
          if G.Prisoners[Index].Falling then
            AddLog(G, 'No nerve trick helps while falling.')
          else if G.Prisoners[Index].Nerve = 0 then
            AddLog(G, 'No nerve remains.')
          else if G.Prisoners[Index].BonusAction then
            AddLog(G, 'An extra action is already queued.')
          else
          begin
            Dec(G.Prisoners[Index].Nerve);
            G.Prisoners[Index].BonusAction := True;
            AddLog(G, PrisonerName(Index) + ' steels up for one extra action.');
          end;
        end;
      'S':
        begin
          if G.Prisoners[Index].Falling then
            AddLog(G, 'Choose a re-entry direction instead of staying.')
          else if StayPrisoner(G, Index) then
          begin
            ResolveStayMonsterReplacement(G, Index);
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
              AddLog(G, PrisonerName(Index) + ' may now take the turn normally.');
            end
            else
              AddLog(G, 'No legal landing from that edge.');
          end
          else if MovePrisoner(G, Index, Dir) then
          begin
            DidMove := True;
            Done := True;
          end
          else
            AddLog(G, 'No connected passage that way.');
        end;
    end;
  until Done or (G.Phase = gpLoss);

  if Done then
  begin
    PostActionUpdate(G, Index, OldX, OldY, DidMove);
    ResolveOneAction := True;
  end;
end;

procedure ResolveFinalFlicker(var G: TGameState; Index: Byte);
var
  CancelLoss: Boolean;
begin
  if G.Phase <> gpFinal then
    Exit;
  if G.Phase in [gpWin, gpLoss] then
    Exit;

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
    RemoveOneFlickerTile(G);

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
    if G.Prisoners[Index].BonusAction then
      G.Prisoners[Index].BonusAction := False;

    if G.Prisoners[Index].Falling and (not HasAnyReEntry(G, Index)) then
    begin
      G.Phase := gpLoss;
      AddLog(G, PrisonerName(Index) + ' cannot find any path back into the maze.');
      Break;
    end;

    if not ResolveOneAction(G, Index) then
      Break;
    if G.Phase in [gpWin, gpLoss] then
      Break;

    while G.Prisoners[Index].BonusAction do
    begin
      G.Prisoners[Index].BonusAction := False;
      AddLog(G, PrisonerName(Index) + ' takes the extra action granted by nerve.');
      if not ResolveOneAction(G, Index) then
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
    WriteAt(3, 24, 'Game over. The dark kept the cage. Press any key.            ');
  WaitForKey;
end;

var
  Game: TGameState;

begin
  ClrScr;
  TitleScreen;
  InitGame(Game);
  RebuildOccupancy(Game);
  RecomputeLighting(Game);
  CollapseDarkness(Game);
  RebuildOccupancy(Game);
  CheckWinLoss(Game);
  Game.PromptPlacement := True;
  GameLoop(Game);
  ShowEnding(Game);
end.
