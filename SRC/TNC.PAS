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

procedure PostActionUpdate(var G: TGameState; Index, OldX, OldY: Byte; DidMove: Boolean);
var
  Victim: Byte;
  VictimMask: Byte;
  Brace: Boolean;
begin
  RebuildOccupancy(G);
  ResolveRelights(G);
  RecomputeLighting(G);

  if DidMove then
    VictimMask := WaxEscapeVictimMask(G, Index, OldX, OldY) or WaxContactVictimMask(G, Index)
  else
    VictimMask := WaxContactVictimMask(G, Index);

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
    ResolveRelights(G);
    RebuildOccupancy(G);
    RecomputeLighting(G);
  end;

  RebuildOccupancy(G);
  CollapseDarkness(G);
  RebuildOccupancy(G);
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
            Done := True
          else
            AddLog(G, 'That prisoner cannot stay in the dark without nerve.');
        end;
      'M':
        begin
          if G.Prisoners[Index].Falling then
          begin
            if ResolveFallingEntry(G, Index, Dir) then
              Done := True
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
  GameLoop(Game);
  ShowEnding(Game);
end.
