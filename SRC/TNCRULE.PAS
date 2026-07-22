unit TNCRule;

interface

uses
  TNCDef,
  TNCGen;

procedure RebuildOccupancy(var G: TGameState);
procedure ResolveRelights(var G: TGameState);
procedure RecomputeLighting(var G: TGameState);
function CanMoveDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function MoveRequiresCharge(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function MovePrisoner(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function StayPrisoner(var G: TGameState; Index: Byte): Boolean;
procedure BeginPrisonerFall(var G: TGameState; Index: Byte);
function ChooseFallEdge(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
procedure ApplyPendingNerve(var G: TGameState; Index: Byte);
function CanPassKey(const G: TGameState; Index: Byte): Boolean;
procedure BuildKeyPassTargets(const G: TGameState; Index: Byte; var Eligible: TBoolGrid;
  var Count: Byte);
function PassKeyToCell(var G: TGameState; Index, X, Y: Byte): Boolean;
function HasAnyReEntry(const G: TGameState; Index: Byte): Boolean;
function CanReEnterDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function ResolveFallingEntry(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
procedure BuildFallingTargets(const G: TGameState; Index: Byte; Dir: TDirection;
  var EmptyEligible, ExistingEligible: TBoolGrid; var EmptyCount, ExistingCount: Byte);
function LandFallingPrisoner(var G: TGameState; Index, X, Y: Byte): Boolean;
function CanLandingScrambleDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function ScrambleLandingPrisoner(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function ScrambleFromMonster(var G: TGameState; Index: Byte; Dir: TDirection;
  DiscardOrigin: Boolean; OriginX, OriginY: Byte): Boolean;
function ConvertMonsterToPit(var G: TGameState; X, Y: Byte): Boolean;
function DiscardMonsterTile(var G: TGameState; X, Y: Byte): Boolean;
procedure BuildMoveTriggeredMonsters(const BeforeG, AfterG: TGameState; ActiveIndex, OldX, OldY: Byte;
  var Scheduled: TBoolGrid);
procedure BuildLandingTriggeredMonsters(const G: TGameState; Index: Byte; var Scheduled: TBoolGrid);
function MonsterVictimMaskAndChains(const G: TGameState; MX, MY: Byte;
  var Scheduled: TBoolGrid; const Resolved: TBoolGrid): Byte;
function PrisonerOnMonster(const G: TGameState; Index: Byte): Boolean;
procedure BuildStayMonsterTargets(const G: TGameState; Index: Byte; var Eligible: TBoolGrid;
  var Count: Byte);
procedure PlacePendingStayMonster(var G: TGameState; X, Y: Byte);
procedure ApplyMonsterHit(var G: TGameState; Index: Byte; Count: Byte; Brace: Boolean);
procedure ClearFreshTiles(var G: TGameState);
procedure CollapseDarkness(var G: TGameState);
procedure BuildFlickerTargets(const G: TGameState; var Eligible: TBoolGrid; var Count: Byte);
function RemoveFlickerTileAt(var G: TGameState; X, Y: Byte): Boolean;
procedure CheckPhaseTransitions(var G: TGameState);
procedure CheckWinLoss(var G: TGameState);
function PrisonerCanAct(const G: TGameState; Index: Byte): Boolean;
function RemainingKeys(const G: TGameState): Byte;
function RemainingGates(const G: TGameState): Byte;
function PrisonerOnBreakableTile(const G: TGameState; Index: Byte): Boolean;
function PrisonerOnPit(const G: TGameState; Index: Byte): Boolean;
function PrisonerHasAnyMove(const G: TGameState; Index: Byte): Boolean;

implementation

procedure RebuildOccupancy(var G: TGameState);
var
  X, Y, I: Byte;
begin
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      G.Board[X, Y].Flags := G.Board[X, Y].Flags - [cfOccupied];

  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].Alive and G.Prisoners[I].Started and (not G.Prisoners[I].Falling) then
      if IsPresent(G.Board[G.Prisoners[I].X, G.Prisoners[I].Y]) then
        G.Board[G.Prisoners[I].X, G.Prisoners[I].Y].Flags :=
          G.Board[G.Prisoners[I].X, G.Prisoners[I].Y].Flags + [cfOccupied];
end;

function AdjacentLitAlly(const G: TGameState; Index: Byte): Boolean;
var
  I: Byte;
  P, Q: TPrisoner;
  D: TDirection;
begin
  AdjacentLitAlly := False;
  P := G.Prisoners[Index];
  for I := 0 to PrisonerCount - 1 do
    if I <> Index then
    begin
      Q := G.Prisoners[I];
      if Q.Alive and Q.Started and Q.Lit and (not Q.Falling) then
      begin
        if (P.X = Q.X) and (P.Y = Q.Y) then
        begin
          AdjacentLitAlly := True;
          Exit;
        end;
        for D := dirNorth to dirWest do
          if (WrapX(Integer(P.X) + DirX[D]) = Q.X) and
             (WrapY(Integer(P.Y) + DirY[D]) = Q.Y) and
             IsPresent(G.Board[P.X, P.Y]) and
             IsPresent(G.Board[Q.X, Q.Y]) and
             CellOpen(G.Board[P.X, P.Y], D) and
             CellOpen(G.Board[Q.X, Q.Y], OppositeDir(D)) then
          begin
            AdjacentLitAlly := True;
            Exit;
          end;
      end;
    end;
end;

procedure ResolveRelights(var G: TGameState);
var
  I: Byte;
  Changed: Boolean;
begin
  { Repeat so a newly relit candle can relay the flame through a connected
    group regardless of prisoner index order. }
  repeat
    Changed := False;
    for I := 0 to PrisonerCount - 1 do
      if G.Prisoners[I].Alive and G.Prisoners[I].Started and
         (not G.Prisoners[I].Falling) and (not G.Prisoners[I].Lit) then
        if AdjacentLitAlly(G, I) then
        begin
          G.Prisoners[I].Lit := True;
          Changed := True;
          AddLog(G, PrisonerName(I) + ' is relit by a nearby flame.');
        end;
  until not Changed;
end;

procedure RecomputeLighting(var G: TGameState);
var
  X, Y, I: Byte;
  D: TDirection;
  NX, NY: Byte;
  Eligible: TBoolGrid;
  RequiredMasks: TMaskGrid;
  Count: Byte;
begin
  repeat
    for X := 0 to BoardW - 1 do
      for Y := 0 to BoardH - 1 do
        G.Board[X, Y].Flags := G.Board[X, Y].Flags - [cfLit];

    FillChar(Eligible, SizeOf(Eligible), 0);
    FillChar(RequiredMasks, SizeOf(RequiredMasks), 0);
    Count := 0;

    for I := 0 to PrisonerCount - 1 do
      if G.Prisoners[I].Alive and G.Prisoners[I].Started and
         G.Prisoners[I].Lit and (not G.Prisoners[I].Falling) then
      begin
        X := G.Prisoners[I].X;
        Y := G.Prisoners[I].Y;
        if IsPresent(G.Board[X, Y]) then
        begin
          G.Board[X, Y].Flags := G.Board[X, Y].Flags + [cfLit];
          G.Board[X, Y].LastLitTurn := G.TurnNumber;
          for D := dirNorth to dirWest do
          begin
            NX := WrapX(Integer(X) + DirX[D]);
            NY := WrapY(Integer(Y) + DirY[D]);
            if CellOpen(G.Board[X, Y], D) and (not IsPresent(G.Board[NX, NY])) and
               (G.Phase = gpMaze) and (G.DrawsRemaining > 0) then
            begin
              if not Eligible[NX, NY] then
              begin
                Eligible[NX, NY] := True;
                Inc(Count);
              end;
              RequiredMasks[NX, NY] := RequiredMasks[NX, NY] or
                                        DirMask(OppositeDir(D));
            end;
            { A passage illuminates the adjacent tile even when that tile's
              wall blocks the connection.  The visible wall remains on the
              board instead of disappearing into darkness. }
            if CellOpen(G.Board[X, Y], D) and IsPresent(G.Board[NX, NY]) then
            begin
              G.Board[NX, NY].Flags := G.Board[NX, NY].Flags + [cfLit];
              G.Board[NX, NY].LastLitTurn := G.TurnNumber;
            end;
          end;
        end;
      end;

    if (Count = 0) or (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
      Break;
  until not PlaceIlluminationTile(G, Eligible, RequiredMasks);
end;

function IsKeyTileFeature(Feature: TFeature): Boolean;
begin
  IsKeyTileFeature := Feature in [ftKey, ftKeyArmed];
end;

procedure ConvertToPit(var G: TGameState; X, Y: Byte);
begin
  if IsKeyTileFeature(G.Board[X, Y].Feature) then
  begin
    Inc(G.LostKeys);
    AddLog(G, 'An unclaimed key falls into the pit.');
  end;
  G.Board[X, Y].Kind := tkPit;
  G.Board[X, Y].Rot := 0;
  G.Board[X, Y].Feature := ftNone;
  G.Board[X, Y].Flags := G.Board[X, Y].Flags + [cfPresent];
end;

function ConvertMonsterToPit(var G: TGameState; X, Y: Byte): Boolean;
begin
  ConvertMonsterToPit := False;
  if (X >= BoardW) or (Y >= BoardH) then
    Exit;
  if (not IsPresent(G.Board[X, Y])) or
     (G.Board[X, Y].Feature <> ftMonster) then
    Exit;

  ConvertToPit(G, X, Y);
  AddLog(G, 'The charged wax eater collapses into a pit.');
  ConvertMonsterToPit := True;
end;

function DiscardMonsterTile(var G: TGameState; X, Y: Byte): Boolean;
begin
  DiscardMonsterTile := False;
  if (X >= BoardW) or (Y >= BoardH) then
    Exit;
  if (not IsPresent(G.Board[X, Y])) or
     (G.Board[X, Y].Feature <> ftMonster) then
    Exit;

  ClearCell(G.Board[X, Y]);
  AddLog(G, 'The landed-on wax eater is discarded.');
  DiscardMonsterTile := True;
end;

function TileBreaksOnUse(const Cell: TCell): Boolean;
begin
  TileBreaksOnUse := (Cell.Kind = tkStart) or
                     (Cell.Feature in [ftKey, ftKeyArmed,
                                       ftCrumbleFresh, ftCrumbleArmed]);
end;

procedure BeginPrisonerFall(var G: TGameState; Index: Byte);
begin
  if Index >= PrisonerCount then
    Exit;
  G.Prisoners[Index].Falling := True;
  G.Prisoners[Index].FallEdgeChosen := False;
end;

function ChooseFallEdge(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
begin
  ChooseFallEdge := False;
  if Index >= PrisonerCount then
    Exit;
  if not G.Prisoners[Index].Falling then
    Exit;

  G.Prisoners[Index].FallDir := Dir;
  G.Prisoners[Index].FallEdgeChosen := True;
  AddLog(G, PrisonerName(Index) + ' chooses the ' + DirName(Dir) +
    ' edge for re-entry.');
  ChooseFallEdge := True;
end;

function IsPitCell(const Cell: TCell): Boolean;
begin
  IsPitCell := IsPresent(Cell) and (Cell.Kind = tkPit);
end;

function CanOccupyCell(const G: TGameState; X, Y: Byte): Boolean;
begin
  CanOccupyCell := IsPassable(G.Board[X, Y]) and
                   ((not (cfOccupied in G.Board[X, Y].Flags)) or
                    (G.Board[X, Y].Feature = ftGate));
end;

procedure HandleEntryFeature(var G: TGameState; Index: Byte);
var
  X, Y: Byte;
begin
  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;

  case G.Board[X, Y].Feature of
    ftKey, ftKeyArmed:
      begin
        if not G.Prisoners[Index].HasKey then
        begin
          G.Prisoners[Index].HasKey := True;
          AddLog(G, PrisonerName(Index) + ' claims a key tile.');
          G.Board[X, Y].Feature := ftCrumbleArmed;
          AddLog(G, 'The key tile begins to crack.');
        end
        else if G.Board[X, Y].Feature = ftKey then
        begin
          G.Board[X, Y].Feature := ftKeyArmed;
          AddLog(G, 'The unclaimed key remains as its tile begins to crack.');
        end;
      end;
    ftCrumbleFresh:
      begin
        G.Board[X, Y].Feature := ftCrumbleArmed;
        AddLog(G, PrisonerName(Index) + ' hears stone cracking underfoot.');
      end;
  end;
end;

function CanMoveDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  X, Y, NX, NY: Byte;
begin
  CanMoveDirection := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if not IsPassable(G.Board[X, Y]) then
    Exit;
  if not CellOpen(G.Board[X, Y], Dir) then
    Exit;

  NX := WrapX(Integer(X) + DirX[Dir]);
  NY := WrapY(Integer(Y) + DirY[Dir]);
  if not IsPresent(G.Board[NX, NY]) then
  begin
    if CanGenerateCell(G, NX, NY, OppositeDir(Dir)) then
      CanMoveDirection := True;
    Exit;
  end;

  if IsPitCell(G.Board[NX, NY]) then
    CanMoveDirection := True
  else if CanOccupyCell(G, NX, NY) and CellOpen(G.Board[NX, NY], OppositeDir(Dir)) then
  begin
    if G.Board[NX, NY].Feature = ftMonster then
    begin
      if G.Prisoners[Index].Lit then
        CanMoveDirection := G.Prisoners[Index].Nerve > 0
      else
        CanMoveDirection := True;
    end
    else
      CanMoveDirection := True;
  end;
end;

function MoveRequiresCharge(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  X, Y, NX, NY: Byte;
begin
  MoveRequiresCharge := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) or (not G.Prisoners[Index].Lit) then
    Exit;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if not IsPassable(G.Board[X, Y]) then
    Exit;
  if not CellOpen(G.Board[X, Y], Dir) then
    Exit;

  NX := WrapX(Integer(X) + DirX[Dir]);
  NY := WrapY(Integer(Y) + DirY[Dir]);
  if not IsPresent(G.Board[NX, NY]) then
    Exit;
  if not CellOpen(G.Board[NX, NY], OppositeDir(Dir)) then
    Exit;
  if not CanOccupyCell(G, NX, NY) then
    Exit;
  MoveRequiresCharge := G.Board[NX, NY].Feature = ftMonster;
end;

function MovePrisoner(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  X, Y, NX, NY: Byte;
begin
  MovePrisoner := False;
  if not CanMoveDirection(G, Index, Dir) then
    Exit;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  NX := WrapX(Integer(X) + DirX[Dir]);
  NY := WrapY(Integer(Y) + DirY[Dir]);

  if not IsPresent(G.Board[NX, NY]) then
    if not GenerateCell(G, NX, NY, OppositeDir(Dir)) then
      Exit;

  if TileBreaksOnUse(G.Board[X, Y]) then
  begin
    ConvertToPit(G, X, Y);
    AddLog(G, 'The floor behind a prisoner drops away into a pit.');
  end;

  G.Prisoners[Index].X := NX;
  G.Prisoners[Index].Y := NY;

  if IsPitCell(G.Board[NX, NY]) then
  begin
    BeginPrisonerFall(G, Index);
    AddLog(G, PrisonerName(Index) + ' leaps into a pit and falls.');
    MovePrisoner := True;
    Exit;
  end;

  if not CanOccupyCell(G, NX, NY) then
    Exit;

  AddLog(G, PrisonerName(Index) + ' moves ' + DirName(Dir) + '.');
  HandleEntryFeature(G, Index);
  MovePrisoner := True;
end;

function StayPrisoner(var G: TGameState; Index: Byte): Boolean;
var
  X, Y: Byte;
  Tile: TDrawTile;
  DarkStay: Boolean;
begin
  StayPrisoner := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;

  G.Prisoners[Index].NervePending := False;
  DarkStay := not G.Prisoners[Index].Lit;
  if not G.Prisoners[Index].Lit then
  begin
    if G.Prisoners[Index].Nerve = 0 then
      Exit;
    Dec(G.Prisoners[Index].Nerve);
    AddLog(G, PrisonerName(Index) + ' spends 1 nerve to hold still in darkness.');
  end;

  if not DarkStay then
    G.Prisoners[Index].NervePending := True;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  AddLog(G, PrisonerName(Index) + ' stays put.');
  if DarkStay then
    AddLog(G, 'Lights out staying costs 1 nerve and gains none back.')
  else
    AddLog(G, PrisonerName(Index) + ' will gain nerve after the turn.');

  if DrawTopTile(G, Tile, True) then
  begin
    if Tile.Feature = ftMonster then
    begin
      G.PendingStayMonster := True;
      G.PendingStayIndex := Index;
      AddLog(G, 'Staying drew a wax eater. Choose a connected tile to replace.');
    end
    else
      AddLog(G, 'Staying discards one tile from the stack.');
  end
  else
    AddLog(G, 'No tile remains to discard for staying.');

  if IsPitCell(G.Board[X, Y]) then
  begin
    BeginPrisonerFall(G, Index);
    AddLog(G, PrisonerName(Index) + ' falls from the pit.');
    StayPrisoner := True;
    Exit;
  end;

  if TileBreaksOnUse(G.Board[X, Y]) then
  begin
    ConvertToPit(G, X, Y);
    BeginPrisonerFall(G, Index);
    AddLog(G, PrisonerName(Index) + ' falls as the tile gives way.');
  end;

  StayPrisoner := True;
end;

procedure ApplyPendingNerve(var G: TGameState; Index: Byte);
begin
  if Index >= PrisonerCount then
    Exit;
  if not G.Prisoners[Index].NervePending then
    Exit;

  G.Prisoners[Index].NervePending := False;
  if G.Prisoners[Index].Nerve < MaxNerve then
  begin
    Inc(G.Prisoners[Index].Nerve);
    AddLog(G, PrisonerName(Index) + ' gains 1 nerve at turn end.');
  end
  else
    AddLog(G, PrisonerName(Index) + ' ends the turn at full nerve.');
end;

procedure BuildKeyPassTargets(const G: TGameState; Index: Byte; var Eligible: TBoolGrid;
  var Count: Byte);
var
  X, Y, NX, NY, I: Byte;
  D: TDirection;
begin
  FillChar(Eligible, SizeOf(Eligible), 0);
  Count := 0;

  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;
  if not G.Prisoners[Index].HasKey then
    Exit;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if not IsPassable(G.Board[X, Y]) then
    Exit;

  for D := dirNorth to dirWest do
    if CellOpen(G.Board[X, Y], D) then
    begin
      NX := WrapX(Integer(X) + DirX[D]);
      NY := WrapY(Integer(Y) + DirY[D]);
      if IsPassable(G.Board[NX, NY]) and CellOpen(G.Board[NX, NY], OppositeDir(D)) then
        for I := 0 to PrisonerCount - 1 do
          if (I <> Index) and G.Prisoners[I].Alive and G.Prisoners[I].Started and
             (not G.Prisoners[I].Falling) and
             (not G.Prisoners[I].HasKey) and
             (G.Prisoners[I].X = NX) and (G.Prisoners[I].Y = NY) then
          begin
            if not Eligible[NX, NY] then
            begin
              Eligible[NX, NY] := True;
              Inc(Count);
            end;
            Break;
          end;
    end;
end;

function CanPassKey(const G: TGameState; Index: Byte): Boolean;
var
  Eligible: TBoolGrid;
  Count: Byte;
begin
  BuildKeyPassTargets(G, Index, Eligible, Count);
  CanPassKey := Count > 0;
end;

function PassKeyToCell(var G: TGameState; Index, X, Y: Byte): Boolean;
var
  I: Byte;
  Eligible: TBoolGrid;
  Count: Byte;
begin
  PassKeyToCell := False;
  if not G.Prisoners[Index].HasKey then
    Exit;
  if (X >= BoardW) or (Y >= BoardH) then
    Exit;

  BuildKeyPassTargets(G, Index, Eligible, Count);
  if (Count = 0) or (not Eligible[X, Y]) then
    Exit;

  for I := 0 to PrisonerCount - 1 do
    if (I <> Index) and G.Prisoners[I].Alive and G.Prisoners[I].Started and
       (not G.Prisoners[I].Falling) and
       (not G.Prisoners[I].HasKey) and
       (G.Prisoners[I].X = X) and (G.Prisoners[I].Y = Y) then
    begin
      G.Prisoners[Index].HasKey := False;
      G.Prisoners[I].HasKey := True;
      AddLog(G, PrisonerName(Index) + ' passes a key to ' + PrisonerName(I) + '.');
      { Taking a key is free.  If the giver is standing on another Key tile,
        the newly freed hand claims that key immediately. }
      HandleEntryFeature(G, Index);
      PassKeyToCell := True;
      Exit;
    end;
end;

procedure BuildFallingTargets(const G: TGameState; Index: Byte; Dir: TDirection;
  var EmptyEligible, ExistingEligible: TBoolGrid; var EmptyCount, ExistingCount: Byte);
var
  Step, TX, TY: Byte;
begin
  FillChar(EmptyEligible, SizeOf(EmptyEligible), 0);
  FillChar(ExistingEligible, SizeOf(ExistingEligible), 0);
  EmptyCount := 0;
  ExistingCount := 0;

  if (not G.Prisoners[Index].Falling) or
     (not G.Prisoners[Index].FallEdgeChosen) or
     (Dir <> G.Prisoners[Index].FallDir) then
    Exit;

  case Dir of
    dirNorth:
      begin
        for Step := 0 to BoardH - 1 do
        begin
          TX := G.Prisoners[Index].X;
          TY := Step;
          if not IsPresent(G.Board[TX, TY]) then
          begin
            EmptyEligible[TX, TY] := True;
            Inc(EmptyCount);
          end
          else if IsPassable(G.Board[TX, TY]) and
                  ((not (cfOccupied in G.Board[TX, TY].Flags)) or (G.Board[TX, TY].Feature = ftGate)) then
          begin
            ExistingEligible[TX, TY] := True;
            Inc(ExistingCount);
          end;
        end;
      end;
    dirSouth:
      begin
        for Step := 0 to BoardH - 1 do
        begin
          TX := G.Prisoners[Index].X;
          TY := BoardH - 1 - Step;
          if not IsPresent(G.Board[TX, TY]) then
          begin
            EmptyEligible[TX, TY] := True;
            Inc(EmptyCount);
          end
          else if IsPassable(G.Board[TX, TY]) and
                  ((not (cfOccupied in G.Board[TX, TY].Flags)) or (G.Board[TX, TY].Feature = ftGate)) then
          begin
            ExistingEligible[TX, TY] := True;
            Inc(ExistingCount);
          end;
        end;
      end;
    dirWest:
      begin
        for Step := 0 to BoardW - 1 do
        begin
          TX := Step;
          TY := G.Prisoners[Index].Y;
          if not IsPresent(G.Board[TX, TY]) then
          begin
            EmptyEligible[TX, TY] := True;
            Inc(EmptyCount);
          end
          else if IsPassable(G.Board[TX, TY]) and
                  ((not (cfOccupied in G.Board[TX, TY].Flags)) or (G.Board[TX, TY].Feature = ftGate)) then
          begin
            ExistingEligible[TX, TY] := True;
            Inc(ExistingCount);
          end;
        end;
      end;
    dirEast:
      begin
        for Step := 0 to BoardW - 1 do
        begin
          TX := BoardW - 1 - Step;
          TY := G.Prisoners[Index].Y;
          if not IsPresent(G.Board[TX, TY]) then
          begin
            EmptyEligible[TX, TY] := True;
            Inc(EmptyCount);
          end
          else if IsPassable(G.Board[TX, TY]) and
                  ((not (cfOccupied in G.Board[TX, TY].Flags)) or (G.Board[TX, TY].Feature = ftGate)) then
          begin
            ExistingEligible[TX, TY] := True;
            Inc(ExistingCount);
          end;
        end;
      end;
  end;
end;

function HasAnyReEntry(const G: TGameState; Index: Byte): Boolean;
var
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
begin
  HasAnyReEntry := False;
  if (Index >= PrisonerCount) or (not G.Prisoners[Index].Falling) or
     (not G.Prisoners[Index].FallEdgeChosen) then
    Exit;
  BuildFallingTargets(G, Index, G.Prisoners[Index].FallDir,
    EmptyEligible, ExistingEligible, EmptyCount, ExistingCount);
  HasAnyReEntry := ((EmptyCount > 0) and (G.DrawsRemaining > 0)) or
                   ((EmptyCount = 0) and (ExistingCount > 0));
end;

function CanReEnterDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
begin
  BuildFallingTargets(G, Index, Dir, EmptyEligible, ExistingEligible, EmptyCount, ExistingCount);
  CanReEnterDirection := ((EmptyCount > 0) and (G.DrawsRemaining > 0)) or
                         ((EmptyCount = 0) and (ExistingCount > 0));
end;

function LandFallingPrisoner(var G: TGameState; Index, X, Y: Byte): Boolean;
var
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
begin
  LandFallingPrisoner := False;
  if (Index >= PrisonerCount) or (X >= BoardW) or (Y >= BoardH) then
    Exit;
  if (not G.Prisoners[Index].Falling) or
     (not G.Prisoners[Index].FallEdgeChosen) then
    Exit;

  BuildFallingTargets(G, Index, G.Prisoners[Index].FallDir,
    EmptyEligible, ExistingEligible, EmptyCount, ExistingCount);

  if not IsPresent(G.Board[X, Y]) then
  begin
    if (not EmptyEligible[X, Y]) or (G.DrawsRemaining = 0) then
      Exit;
    if not PlaceFreeTileAt(G, X, Y) then
      Exit;
  end
  else
  begin
    if (EmptyCount > 0) or (not ExistingEligible[X, Y]) then
      Exit;
  end;

  G.Prisoners[Index].X := X;
  G.Prisoners[Index].Y := Y;
  G.Prisoners[Index].Falling := False;
  G.Prisoners[Index].FallEdgeChosen := False;
  AddLog(G, PrisonerName(Index) + ' lands back in the maze.');
  HandleEntryFeature(G, Index);
  if IsPresent(G.Board[X, Y]) and (G.Board[X, Y].Feature = ftMonster) then
  begin
    G.PendingLandingMonster := True;
    G.PendingLandingIndex := Index;
    AddLog(G, 'A wax eater waits on the landing tile.');
  end;
  LandFallingPrisoner := True;
end;

function ResolveFallingEntry(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
  X, Y: Byte;
begin
  ResolveFallingEntry := False;
  BuildFallingTargets(G, Index, Dir, EmptyEligible, ExistingEligible, EmptyCount, ExistingCount);
  if EmptyCount > 0 then
  begin
    if G.DrawsRemaining = 0 then
      Exit;
    for Y := 0 to BoardH - 1 do
      for X := 0 to BoardW - 1 do
        if EmptyEligible[X, Y] then
        begin
          ResolveFallingEntry := LandFallingPrisoner(G, Index, X, Y);
          Exit;
        end;
  end
  else if ExistingCount > 0 then
    for Y := 0 to BoardH - 1 do
      for X := 0 to BoardW - 1 do
        if ExistingEligible[X, Y] then
        begin
          ResolveFallingEntry := LandFallingPrisoner(G, Index, X, Y);
          Exit;
        end;
end;

function CanLandingScrambleDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  X, Y, NX, NY: Byte;
begin
  CanLandingScrambleDirection := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;
  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if not IsPresent(G.Board[X, Y]) then
    Exit;
  NX := WrapX(Integer(X) + DirX[Dir]);
  NY := WrapY(Integer(Y) + DirY[Dir]);
  if not IsPresent(G.Board[NX, NY]) then
  begin
    CanLandingScrambleDirection := G.DrawsRemaining > 0;
    Exit;
  end;
  if IsPassable(G.Board[NX, NY]) and
     ((not (cfOccupied in G.Board[NX, NY].Flags)) or (G.Board[NX, NY].Feature = ftGate)) then
    CanLandingScrambleDirection := True;
end;

function ScrambleLandingPrisoner(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  X, Y, NX, NY: Byte;
begin
  ScrambleLandingPrisoner := False;
  if not CanLandingScrambleDirection(G, Index, Dir) then
    Exit;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  NX := WrapX(Integer(X) + DirX[Dir]);
  NY := WrapY(Integer(Y) + DirY[Dir]);
  if not IsPresent(G.Board[NX, NY]) then
    if not PlaceFreeTileAt(G, NX, NY) then
      Exit;

  G.Prisoners[Index].X := NX;
  G.Prisoners[Index].Y := NY;
  AddLog(G, PrisonerName(Index) + ' scrambles ' + DirName(Dir) + ' from the monster.');
  HandleEntryFeature(G, Index);
  ScrambleLandingPrisoner := True;
end;

function ScrambleFromMonster(var G: TGameState; Index: Byte; Dir: TDirection;
  DiscardOrigin: Boolean; OriginX, OriginY: Byte): Boolean;
begin
  ScrambleFromMonster := False;
  if not ScrambleLandingPrisoner(G, Index, Dir) then
    Exit;
  if DiscardOrigin then
    DiscardMonsterTile(G, OriginX, OriginY);
  ScrambleFromMonster := True;
end;

function MonsterSeesCell(const G: TGameState; MX, MY, TX, TY: Byte; var HitDir: TDirection): Boolean;
var
  D: TDirection;
  CX, CY, NX, NY, Limit, Step: Byte;
begin
  MonsterSeesCell := False;
  for D := dirNorth to dirWest do
  begin
    CX := MX;
    CY := MY;
    if (D = dirNorth) or (D = dirSouth) then
      Limit := BoardH - 1
    else
      Limit := BoardW - 1;

    for Step := 1 to Limit do
    begin
      if (not IsPresent(G.Board[CX, CY])) or (not CellOpen(G.Board[CX, CY], D)) then
        Break;

      NX := WrapX(Integer(CX) + DirX[D]);
      NY := WrapY(Integer(CY) + DirY[D]);
      if (not IsPresent(G.Board[NX, NY])) or (G.Board[NX, NY].Kind = tkPit) then
        Break;
      if not CellOpen(G.Board[NX, NY], OppositeDir(D)) then
        Break;

      CX := NX;
      CY := NY;
      if (CX = TX) and (CY = TY) then
      begin
        HitDir := D;
        MonsterSeesCell := True;
        Exit;
      end;
    end;
  end;
end;

type
  TMonsterGrid = array[0..BoardW - 1, 0..BoardH - 1] of Boolean;
  TPrisonerMarks = array[0..PrisonerCount - 1] of Boolean;
  TMonsterQueue = array[0..(BoardW * BoardH) - 1] of Byte;

function PrisonerOnMonster(const G: TGameState; Index: Byte): Boolean;
var
  X, Y: Byte;
begin
  PrisonerOnMonster := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;
  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  PrisonerOnMonster := IsPresent(G.Board[X, Y]) and
                       (G.Board[X, Y].Feature = ftMonster) and
                       (G.Board[X, Y].Kind <> tkPit);
end;

procedure QueueMonster(const G: TGameState; X, Y: Byte; var Scheduled: TMonsterGrid;
  var QueueX, QueueY: TMonsterQueue; var Tail: Byte);
begin
  if not IsPresent(G.Board[X, Y]) then
    Exit;
  if G.Board[X, Y].Feature <> ftMonster then
    Exit;
  if Scheduled[X, Y] then
    Exit;

  Scheduled[X, Y] := True;
  QueueX[Tail] := X;
  QueueY[Tail] := Y;
  Inc(Tail);
end;

procedure MarkPrisonersAtCell(const G: TGameState; X, Y: Byte; var Seen: TPrisonerMarks;
  var VictimMask: Byte);
var
  I: Byte;
begin
  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].Alive and G.Prisoners[I].Started and
       (not G.Prisoners[I].Falling) and
       (G.Prisoners[I].X = X) and (G.Prisoners[I].Y = Y) and
       (not Seen[I]) then
    begin
      Seen[I] := True;
      VictimMask := VictimMask or (1 shl I);
    end;
end;

function MonsterVictimMaskAndChains(const G: TGameState; MX, MY: Byte;
  var Scheduled: TBoolGrid; const Resolved: TBoolGrid): Byte;
var
  D: TDirection;
  CX, CY, NX, NY, Limit, Step: Byte;
  Seen: TPrisonerMarks;
  Mask: Byte;
begin
  FillChar(Seen, SizeOf(Seen), 0);
  Mask := 0;
  MarkPrisonersAtCell(G, MX, MY, Seen, Mask);

  for D := dirNorth to dirWest do
  begin
    CX := MX;
    CY := MY;
    if (D = dirNorth) or (D = dirSouth) then
      Limit := BoardH - 1
    else
      Limit := BoardW - 1;

    for Step := 1 to Limit do
    begin
      if (not IsPresent(G.Board[CX, CY])) or (not CellOpen(G.Board[CX, CY], D)) then
        Break;

      NX := WrapX(Integer(CX) + DirX[D]);
      NY := WrapY(Integer(CY) + DirY[D]);
      if (not IsPresent(G.Board[NX, NY])) or (G.Board[NX, NY].Kind = tkPit) then
        Break;
      if not CellOpen(G.Board[NX, NY], OppositeDir(D)) then
        Break;

      CX := NX;
      CY := NY;
      MarkPrisonersAtCell(G, CX, CY, Seen, Mask);
      if (G.Board[CX, CY].Feature = ftMonster) and (not Resolved[CX, CY]) then
        Scheduled[CX, CY] := True;
    end;
  end;
  MonsterVictimMaskAndChains := Mask;
end;

function MonsterTriggeredByMove(const BeforeG, AfterG: TGameState; MX, MY, OldX, OldY, NewX, NewY: Byte): Boolean;
var
  OldSeen, NewSeen: Boolean;
  OldDir, NewDir: TDirection;
begin
  MonsterTriggeredByMove := False;

  if (MX = NewX) and (MY = NewY) then
  begin
    MonsterTriggeredByMove := True;
    Exit;
  end;

  OldSeen := MonsterSeesCell(BeforeG, MX, MY, OldX, OldY, OldDir);
  NewSeen := MonsterSeesCell(AfterG, MX, MY, NewX, NewY, NewDir);
  if OldSeen or NewSeen then
  begin
    MonsterTriggeredByMove := True;
    Exit;
  end;
end;

procedure BuildMoveTriggeredMonsters(const BeforeG, AfterG: TGameState; ActiveIndex, OldX, OldY: Byte;
  var Scheduled: TBoolGrid);
var
  X, Y: Byte;
begin
  FillChar(Scheduled, SizeOf(Scheduled), 0);

  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(AfterG.Board[X, Y]) and (AfterG.Board[X, Y].Feature = ftMonster) then
        if ((AfterG.Prisoners[ActiveIndex].X = X) and (AfterG.Prisoners[ActiveIndex].Y = Y)) or
           (((not (cfFresh in AfterG.Board[X, Y].Flags)) and
             MonsterTriggeredByMove(BeforeG, AfterG, X, Y, OldX, OldY,
               AfterG.Prisoners[ActiveIndex].X, AfterG.Prisoners[ActiveIndex].Y))) then
          Scheduled[X, Y] := True;
end;

procedure BuildLandingTriggeredMonsters(const G: TGameState; Index: Byte; var Scheduled: TBoolGrid);
var
  X, Y, MX, MY: Byte;
  HitDir: TDirection;
begin
  FillChar(Scheduled, SizeOf(Scheduled), 0);
  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;

  for MX := 0 to BoardW - 1 do
    for MY := 0 to BoardH - 1 do
      if IsPresent(G.Board[MX, MY]) and (G.Board[MX, MY].Feature = ftMonster) then
        if ((MX = X) and (MY = Y)) or
           (((not (cfFresh in G.Board[MX, MY].Flags)) and
             MonsterSeesCell(G, MX, MY, X, Y, HitDir))) then
          Scheduled[MX, MY] := True;
end;

procedure BuildStayMonsterTargets(const G: TGameState; Index: Byte; var Eligible: TBoolGrid;
  var Count: Byte);
var
  X, Y: Byte;
  D: TDirection;
  NX, NY: Byte;
begin
  FillChar(Eligible, SizeOf(Eligible), 0);
  Count := 0;

  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;
  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if not IsPassable(G.Board[X, Y]) then
    Exit;

  for D := dirNorth to dirWest do
    if CellOpen(G.Board[X, Y], D) then
    begin
      NX := WrapX(Integer(X) + DirX[D]);
      NY := WrapY(Integer(Y) + DirY[D]);
      if IsPassable(G.Board[NX, NY]) and CellOpen(G.Board[NX, NY], OppositeDir(D)) and
         not (cfOccupied in G.Board[NX, NY].Flags) and
         (G.Board[NX, NY].Feature <> ftMonster) then
      begin
        Eligible[NX, NY] := True;
        Inc(Count);
      end;
    end;
end;

procedure PlacePendingStayMonster(var G: TGameState; X, Y: Byte);
begin
  if not G.PendingStayMonster then
    Exit;
  if not IsPresent(G.Board[X, Y]) then
  begin
    G.PendingStayMonster := False;
    Exit;
  end;

  if IsKeyTileFeature(G.Board[X, Y].Feature) then
    Inc(G.LostKeys);
  if G.Board[X, Y].Feature = ftGate then
    Inc(G.LostGates);
  G.Board[X, Y].Kind := tkCross;
  G.Board[X, Y].Rot := 0;
  G.Board[X, Y].Feature := ftMonster;
  G.Board[X, Y].Flags := G.Board[X, Y].Flags + [cfFresh];
  G.PendingStayMonster := False;
  AddLog(G, 'A wax eater replaces a connected tile.');
end;

procedure ApplyMonsterHit(var G: TGameState; Index: Byte; Count: Byte; Brace: Boolean);
var
  Loss: Byte;
begin
  if Count = 0 then
    Exit;

  if Brace and (G.Prisoners[Index].Nerve > 0) then
  begin
    Dec(G.Prisoners[Index].Nerve);
    Loss := Count * 3 - 1;
    AddLog(G, PrisonerName(Index) + ' braces against the dark with nerve.');
  end
  else
    Loss := Count * 3;

  G.Prisoners[Index].Lit := False;
  DiscardDrawTiles(G, Loss);
  AddLog(G, PrisonerName(Index) + ' is struck by wax eaters.');
end;

procedure ClearFreshTiles(var G: TGameState);
var
  X, Y: Byte;
begin
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(G.Board[X, Y]) then
        G.Board[X, Y].Flags := G.Board[X, Y].Flags - [cfFresh];
end;

procedure CollapseDarkness(var G: TGameState);
var
  X, Y: Byte;
begin
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(G.Board[X, Y]) and
         not (cfPermanent in G.Board[X, Y].Flags) and
         not (cfLit in G.Board[X, Y].Flags) and
         not (cfOccupied in G.Board[X, Y].Flags) then
      begin
        if IsKeyTileFeature(G.Board[X, Y].Feature) then
          Inc(G.LostKeys);
        if G.Board[X, Y].Feature = ftGate then
          Inc(G.LostGates);
        ClearCell(G.Board[X, Y]);
      end;
end;

procedure BuildFlickerTargets(const G: TGameState; var Eligible: TBoolGrid; var Count: Byte);
var
  X, Y: Byte;
begin
  FillChar(Eligible, SizeOf(Eligible), 0);
  Count := 0;

  { An occupied tile is a last resort, not a protected space. }
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(G.Board[X, Y]) and
         (cfLit in G.Board[X, Y].Flags) and
         not (cfPermanent in G.Board[X, Y].Flags) and
         not (cfOccupied in G.Board[X, Y].Flags) then
      begin
        Eligible[X, Y] := True;
        Inc(Count);
      end;

  if Count = 0 then
    for X := 0 to BoardW - 1 do
      for Y := 0 to BoardH - 1 do
        if IsPresent(G.Board[X, Y]) and
           (cfLit in G.Board[X, Y].Flags) and
           not (cfPermanent in G.Board[X, Y].Flags) and
           (cfOccupied in G.Board[X, Y].Flags) then
        begin
          Eligible[X, Y] := True;
          Inc(Count);
        end;
end;

function RemoveFlickerTileAt(var G: TGameState; X, Y: Byte): Boolean;
var
  Eligible: TBoolGrid;
  Count: Byte;
  WasOccupied: Boolean;
begin
  RemoveFlickerTileAt := False;
  if (X >= BoardW) or (Y >= BoardH) then
    Exit;

  BuildFlickerTargets(G, Eligible, Count);
  if (Count = 0) or (not Eligible[X, Y]) then
    Exit;

  WasOccupied := cfOccupied in G.Board[X, Y].Flags;
  if IsKeyTileFeature(G.Board[X, Y].Feature) then
    Inc(G.LostKeys);
  if G.Board[X, Y].Feature = ftGate then
    Inc(G.LostGates);
  ClearCell(G.Board[X, Y]);
  if WasOccupied then
  begin
    G.Phase := gpLoss;
    AddLog(G, 'A final flicker opens beneath a prisoner.');
  end
  else
    AddLog(G, 'The chosen final flicker is swallowed by darkness.');
  RemoveFlickerTileAt := True;
end;

procedure CheckPhaseTransitions(var G: TGameState);
begin
  if (G.Phase = gpMaze) and (G.DrawsRemaining = 0) then
  begin
    G.Phase := gpFinal;
    AddLog(G, 'The tile stack is gone. Final flickers begin.');
  end;
end;

function CountHeldKeys(const G: TGameState): Byte;
var
  I: Byte;
  Count: Byte;
begin
  Count := 0;
  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].HasKey then
      Inc(Count);
  CountHeldKeys := Count;
end;

function CountBoardFeature(const G: TGameState; Feature: TFeature): Byte;
var
  X, Y: Byte;
  Count: Byte;
begin
  Count := 0;
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(G.Board[X, Y]) and (G.Board[X, Y].Feature = Feature) then
        Inc(Count);
  CountBoardFeature := Count;
end;

function RemainingKeys(const G: TGameState): Byte;
var
  Count: Byte;
begin
  Count := CountHeldKeys(G) + CountBoardFeature(G, ftKey) +
           CountBoardFeature(G, ftKeyArmed);
  if G.Phase = gpMaze then
    Inc(Count, G.FeatureKeys);
  RemainingKeys := Count;
end;

function RemainingGates(const G: TGameState): Byte;
var
  Count: Byte;
begin
  Count := CountBoardFeature(G, ftGate);
  if G.Phase = gpMaze then
    Inc(Count, G.FeatureGates);
  RemainingGates := Count;
end;

type
  TReachByPrisoner = array[0..PrisonerCount - 1] of TBoolGrid;
  TReachQueue = array[0..(BoardW * BoardH) - 1] of Byte;

procedure BuildPrisonerReach(const G: TGameState; Index: Byte; var Reach: TBoolGrid);
var
  QueueX, QueueY: TReachQueue;
  Head, Tail: Byte;
  X, Y, NX, NY: Byte;
  D: TDirection;

  procedure Enqueue(TX, TY: Byte);
  begin
    if IsPassable(G.Board[TX, TY]) and (not Reach[TX, TY]) then
    begin
      Reach[TX, TY] := True;
      QueueX[Tail] := TX;
      QueueY[Tail] := TY;
      Inc(Tail);
    end;
  end;

  procedure AddFallLine(FX, FY: Byte; FallDir: TDirection);
  var
    K: Byte;
    FullLine: Boolean;
  begin
    { With no Draw Stack, an existing tile can be used only when the chosen
      row or column contains no empty landing space. }
    if FallDir in [dirWest, dirEast] then
    begin
      FullLine := True;
      for K := 0 to BoardW - 1 do
        if not IsPresent(G.Board[K, FY]) then
          FullLine := False;
      if FullLine then
        for K := 0 to BoardW - 1 do
          Enqueue(K, FY);
    end
    else
    begin
      FullLine := True;
      for K := 0 to BoardH - 1 do
        if not IsPresent(G.Board[FX, K]) then
          FullLine := False;
      if FullLine then
        for K := 0 to BoardH - 1 do
          Enqueue(FX, K);
    end;
  end;

  procedure AddFallLandings(FX, FY: Byte);
  begin
    { A future fall may choose either axis.  A prisoner already falling is
      handled separately with the edge locked when the fall began. }
    AddFallLine(FX, FY, dirNorth);
    AddFallLine(FX, FY, dirWest);
  end;

begin
  FillChar(Reach, SizeOf(Reach), 0);
  Head := 0;
  Tail := 0;
  if (Index >= PrisonerCount) or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;

  if G.Prisoners[Index].Falling then
  begin
    if G.Prisoners[Index].FallEdgeChosen then
      AddFallLine(G.Prisoners[Index].X, G.Prisoners[Index].Y,
        G.Prisoners[Index].FallDir)
  end
  else
    Enqueue(G.Prisoners[Index].X, G.Prisoners[Index].Y);

  while Head < Tail do
  begin
    X := QueueX[Head];
    Y := QueueY[Head];
    Inc(Head);

    for D := dirNorth to dirWest do
      if CellOpen(G.Board[X, Y], D) then
      begin
        NX := WrapX(Integer(X) + DirX[D]);
        NY := WrapY(Integer(Y) + DirY[D]);
        if IsPassable(G.Board[NX, NY]) and
           CellOpen(G.Board[NX, NY], OppositeDir(D)) then
          Enqueue(NX, NY)
        else if IsPitCell(G.Board[NX, NY]) then
          AddFallLandings(NX, NY);
      end;

    if TileBreaksOnUse(G.Board[X, Y]) then
      AddFallLandings(X, Y);
  end;
end;

procedure BuildFinalReachability(const G: TGameState; var Reach: TReachByPrisoner);
var
  I: Byte;
begin
  for I := 0 to PrisonerCount - 1 do
    BuildPrisonerReach(G, I, Reach[I]);
end;

function CommonGateReachable(const G: TGameState;
  const Reach: TReachByPrisoner): Boolean;
var
  X, Y, I: Byte;
  AllReach: Boolean;
begin
  CommonGateReachable := False;
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(G.Board[X, Y]) and
         (G.Board[X, Y].Feature = ftGate) then
      begin
        AllReach := True;
        for I := 0 to PrisonerCount - 1 do
          if not Reach[I][X, Y] then
            AllReach := False;
        if AllReach then
        begin
          CommonGateReachable := True;
          Exit;
        end;
      end;
end;

function ReachableKeyCapacity(const G: TGameState;
  const Reach: TReachByPrisoner): Byte;
var
  X, Y, I, Count: Byte;
  AnyReach: Boolean;
begin
  Count := CountHeldKeys(G);
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(G.Board[X, Y]) and
         IsKeyTileFeature(G.Board[X, Y].Feature) then
      begin
        AnyReach := False;
        for I := 0 to PrisonerCount - 1 do
          if Reach[I][X, Y] then
            AnyReach := True;
        if AnyReach then
          Inc(Count);
      end;
  ReachableKeyCapacity := Count;
end;

function PrisonerOnBreakableTile(const G: TGameState; Index: Byte): Boolean;
var
  X, Y: Byte;
begin
  PrisonerOnBreakableTile := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;
  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if not IsPresent(G.Board[X, Y]) then
    Exit;
  PrisonerOnBreakableTile := TileBreaksOnUse(G.Board[X, Y]);
end;

function PrisonerOnPit(const G: TGameState; Index: Byte): Boolean;
var
  X, Y: Byte;
begin
  PrisonerOnPit := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;
  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if not IsPresent(G.Board[X, Y]) then
    Exit;
  PrisonerOnPit := IsPitCell(G.Board[X, Y]);
end;

function PrisonerHasAnyMove(const G: TGameState; Index: Byte): Boolean;
var
  Dir: TDirection;
begin
  PrisonerHasAnyMove := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;
  for Dir := dirNorth to dirWest do
    if CanMoveDirection(G, Index, Dir) then
    begin
      PrisonerHasAnyMove := True;
      Exit;
    end;
end;

function AllOnSameGate(const G: TGameState): Boolean;
var
  I: Byte;
  GX, GY: Byte;
begin
  AllOnSameGate := False;
  if (not G.Prisoners[0].Started) or G.Prisoners[0].Falling then
    Exit;
  GX := G.Prisoners[0].X;
  GY := G.Prisoners[0].Y;
  if not IsPresent(G.Board[GX, GY]) then
    Exit;
  if G.Board[GX, GY].Feature <> ftGate then
    Exit;

  for I := 1 to PrisonerCount - 1 do
    if (not G.Prisoners[I].Started) or G.Prisoners[I].Falling or
       (G.Prisoners[I].X <> GX) or
       (G.Prisoners[I].Y <> GY) then
      Exit;

  AllOnSameGate := True;
end;

function PrisonerCanAct(const G: TGameState; Index: Byte): Boolean;
var
  Dir: TDirection;
begin
  PrisonerCanAct := False;
  if not G.Prisoners[Index].Alive then
    Exit;
  if not G.Prisoners[Index].Started then
  begin
    PrisonerCanAct := True;
    Exit;
  end;

  if G.Prisoners[Index].Falling then
  begin
    PrisonerCanAct := HasAnyReEntry(G, Index);
    Exit;
  end;

  if G.Prisoners[Index].Lit or (G.Prisoners[Index].Nerve > 0) then
    PrisonerCanAct := True;
  for Dir := dirNorth to dirWest do
    if CanMoveDirection(G, Index, Dir) then
    begin
      PrisonerCanAct := True;
      Exit;
    end;
end;

procedure CheckWinLoss(var G: TGameState);
var
  I: Byte;
  TotalKeyCapacity: Byte;
  GateCapacity: Byte;
  AnyAction: Boolean;
  Reach: TReachByPrisoner;
begin
  if G.Phase in [gpWin, gpLoss] then
    Exit;

  if (CountHeldKeys(G) = 4) and AllOnSameGate(G) then
  begin
    G.Phase := gpWin;
    AddLog(G, 'All four prisoners escape together.');
    Exit;
  end;

  TotalKeyCapacity := RemainingKeys(G);
  if TotalKeyCapacity < 4 then
  begin
    G.Phase := gpLoss;
    AddLog(G, 'Too many keys are gone. Escape is impossible.');
    Exit;
  end;

  GateCapacity := RemainingGates(G);
  if GateCapacity = 0 then
  begin
    G.Phase := gpLoss;
    AddLog(G, 'No gate remains to carry all four prisoners out.');
    Exit;
  end;

  if G.Phase = gpFinal then
  begin
    BuildFinalReachability(G, Reach);
    if ReachableKeyCapacity(G, Reach) < 4 then
    begin
      G.Phase := gpLoss;
      AddLog(G, 'The remaining keys are cut off by darkness.');
      Exit;
    end;
    if not CommonGateReachable(G, Reach) then
    begin
      G.Phase := gpLoss;
      AddLog(G, 'No single gate can still receive every prisoner.');
      Exit;
    end;
  end;

  AnyAction := False;
  for I := 0 to PrisonerCount - 1 do
    if PrisonerCanAct(G, I) then
    begin
      AnyAction := True;
      Break;
    end;
  if not AnyAction then
  begin
    G.Phase := gpLoss;
    AddLog(G, 'The labyrinth has trapped every prisoner.');
  end;
end;

end.
