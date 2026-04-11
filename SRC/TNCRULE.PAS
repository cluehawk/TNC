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
procedure BuildMoveTriggeredMonsters(const BeforeG, AfterG: TGameState; ActiveIndex, OldX, OldY: Byte;
  var Scheduled: TBoolGrid);
procedure BuildLandingTriggeredMonsters(const G: TGameState; Index: Byte; var Scheduled: TBoolGrid);
function MonsterVictimMaskAndChains(const G: TGameState; MX, MY: Byte; var Scheduled: TBoolGrid): Byte;
function PrisonerOnMonster(const G: TGameState; Index: Byte): Boolean;
procedure BuildStayMonsterTargets(const G: TGameState; Index: Byte; var Eligible: TBoolGrid;
  var Count: Byte);
procedure PlacePendingStayMonster(var G: TGameState; X, Y: Byte);
procedure ApplyMonsterHit(var G: TGameState; Index: Byte; Count: Byte; Brace: Boolean);
procedure ClearFreshTiles(var G: TGameState);
procedure CollapseDarkness(var G: TGameState);
function RemoveOneFlickerTile(var G: TGameState): Boolean;
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
begin
  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].Alive and G.Prisoners[I].Started and
       (not G.Prisoners[I].Falling) and (not G.Prisoners[I].Lit) then
      if AdjacentLitAlly(G, I) then
      begin
        G.Prisoners[I].Lit := True;
        AddLog(G, PrisonerName(I) + ' is relit by a nearby flame.');
      end;
end;

procedure RecomputeLighting(var G: TGameState);
var
  X, Y, I: Byte;
  D: TDirection;
  NX, NY: Byte;
  Eligible: TBoolGrid;
  RequiredDirs: TDirGrid;
  Count: Byte;
begin
  repeat
    for X := 0 to BoardW - 1 do
      for Y := 0 to BoardH - 1 do
        G.Board[X, Y].Flags := G.Board[X, Y].Flags - [cfLit];

    FillChar(Eligible, SizeOf(Eligible), 0);
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
                RequiredDirs[NX, NY] := OppositeDir(D);
                Inc(Count);
              end;
            end;
            if IsPresent(G.Board[NX, NY]) and
               (((G.Board[NX, NY].Kind = tkPit)) or
                (CellOpen(G.Board[X, Y], D) and
                 CellOpen(G.Board[NX, NY], OppositeDir(D)))) then
            begin
              G.Board[NX, NY].Flags := G.Board[NX, NY].Flags + [cfLit];
              G.Board[NX, NY].LastLitTurn := G.TurnNumber;
            end;
          end;
        end;
      end;

    if (Count = 0) or (G.Phase <> gpMaze) or (G.DrawsRemaining = 0) then
      Break;
  until not PlaceIlluminationTile(G, Eligible, RequiredDirs);
end;

procedure ConvertToPit(var Cell: TCell);
begin
  Cell.Kind := tkPit;
  Cell.Rot := 0;
  Cell.Feature := ftNone;
  Cell.Flags := Cell.Flags + [cfPresent];
end;

function TileBreaksOnUse(const Cell: TCell): Boolean;
begin
  TileBreaksOnUse := (Cell.Kind = tkStart) or
                     (Cell.Feature in [ftKey, ftCrumbleFresh, ftCrumbleArmed]);
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
    ftKey:
      begin
        if not G.Prisoners[Index].HasKey then
        begin
          G.Prisoners[Index].HasKey := True;
          AddLog(G, PrisonerName(Index) + ' claims a key tile.');
        end;
        G.Board[X, Y].Feature := ftCrumbleArmed;
        AddLog(G, 'The key tile begins to crack.');
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
    ConvertToPit(G.Board[X, Y]);
    AddLog(G, 'The floor behind a prisoner drops away into a pit.');
  end;

  G.Prisoners[Index].X := NX;
  G.Prisoners[Index].Y := NY;

  if IsPitCell(G.Board[NX, NY]) then
  begin
    G.Prisoners[Index].Falling := True;
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
  GainedNerve: Boolean;
  DarkStay: Boolean;
begin
  StayPrisoner := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) or
     (not G.Prisoners[Index].Started) then
    Exit;

  DarkStay := not G.Prisoners[Index].Lit;
  if not G.Prisoners[Index].Lit then
  begin
    if G.Prisoners[Index].Nerve = 0 then
      Exit;
    Dec(G.Prisoners[Index].Nerve);
    AddLog(G, PrisonerName(Index) + ' spends 1 nerve to hold still in darkness.');
  end;

  GainedNerve := False;
  if (not DarkStay) and (G.Prisoners[Index].Nerve < MaxNerve) then
  begin
    Inc(G.Prisoners[Index].Nerve);
    GainedNerve := True;
  end;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  AddLog(G, PrisonerName(Index) + ' stays put.');
  if DarkStay then
    AddLog(G, 'Lights out staying costs 1 nerve and gains none back.')
  else if GainedNerve then
    AddLog(G, PrisonerName(Index) + ' gathers 1 nerve.')
  else
    AddLog(G, PrisonerName(Index) + ' is already at full nerve.');

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
    G.Prisoners[Index].Falling := True;
    AddLog(G, PrisonerName(Index) + ' falls from the pit.');
    StayPrisoner := True;
    Exit;
  end;

  if TileBreaksOnUse(G.Board[X, Y]) then
  begin
    ConvertToPit(G.Board[X, Y]);
    G.Prisoners[Index].Falling := True;
    AddLog(G, PrisonerName(Index) + ' falls as the tile gives way.');
  end;

  StayPrisoner := True;
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
begin
  PassKeyToCell := False;
  if not G.Prisoners[Index].HasKey then
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

  if not G.Prisoners[Index].Falling then
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
  Dir: TDirection;
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
begin
  HasAnyReEntry := False;
  for Dir := dirNorth to dirWest do
  begin
    BuildFallingTargets(G, Index, Dir, EmptyEligible, ExistingEligible, EmptyCount, ExistingCount);
    if ((EmptyCount > 0) and (G.DrawsRemaining > 0)) or (ExistingCount > 0) then
    begin
      HasAnyReEntry := True;
      Exit;
    end;
  end;
end;

function CanReEnterDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  EmptyEligible, ExistingEligible: TBoolGrid;
  EmptyCount, ExistingCount: Byte;
begin
  BuildFallingTargets(G, Index, Dir, EmptyEligible, ExistingEligible, EmptyCount, ExistingCount);
  CanReEnterDirection := ((EmptyCount > 0) and (G.DrawsRemaining > 0)) or (ExistingCount > 0);
end;

function LandFallingPrisoner(var G: TGameState; Index, X, Y: Byte): Boolean;
begin
  LandFallingPrisoner := False;
  if not G.Prisoners[Index].Falling then
    Exit;

  if not IsPresent(G.Board[X, Y]) then
  begin
    if G.DrawsRemaining = 0 then
      Exit;
    if not PlaceFreeTileAt(G, X, Y) then
      Exit;
  end
  else if not CanOccupyCell(G, X, Y) then
    Exit;

  G.Prisoners[Index].X := X;
  G.Prisoners[Index].Y := Y;
  G.Prisoners[Index].Falling := False;
  AddLog(G, PrisonerName(Index) + ' lands back in the maze.');
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
  if (EmptyCount > 0) and (G.DrawsRemaining > 0) then
  begin
    for Y := 0 to BoardH - 1 do
      for X := 0 to BoardW - 1 do
        if EmptyEligible[X, Y] then
        begin
          ResolveFallingEntry := LandFallingPrisoner(G, Index, X, Y);
          Exit;
        end;
  end
  else
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
    if not PlaceFreeTileAtAuto(G, NX, NY) then
      Exit;

  G.Prisoners[Index].X := NX;
  G.Prisoners[Index].Y := NY;
  AddLog(G, PrisonerName(Index) + ' scrambles ' + DirName(Dir) + ' from the monster.');
  ScrambleLandingPrisoner := True;
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

function MonsterVictimMaskAndChains(const G: TGameState; MX, MY: Byte; var Scheduled: TBoolGrid): Byte;
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
      if G.Board[CX, CY].Feature = ftMonster then
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

  if G.Board[X, Y].Feature = ftKey then
    Inc(G.LostKeys);
  if G.Board[X, Y].Feature = ftGate then
    Inc(G.LostGates);
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
        if G.Board[X, Y].Feature = ftKey then
          Inc(G.LostKeys);
        if G.Board[X, Y].Feature = ftGate then
          Inc(G.LostGates);
        ClearCell(G.Board[X, Y]);
      end;
end;

function RemoveOneFlickerTile(var G: TGameState): Boolean;
var
  Scan, Index, X, Y: Word;
begin
  RemoveOneFlickerTile := False;
  for Scan := 0 to (BoardW * BoardH) - 1 do
  begin
    Index := (G.FlickerCursor + Scan) mod (BoardW * BoardH);
    X := Index mod BoardW;
    Y := Index div BoardW;
    if IsPresent(G.Board[X, Y]) and
       (cfLit in G.Board[X, Y].Flags) and
       not (cfPermanent in G.Board[X, Y].Flags) and
       not (cfOccupied in G.Board[X, Y].Flags) then
    begin
      if G.Board[X, Y].Feature = ftKey then
        Inc(G.LostKeys);
      if G.Board[X, Y].Feature = ftGate then
        Inc(G.LostGates);
      ClearCell(G.Board[X, Y]);
      G.FlickerCursor := (Index + 1) mod (BoardW * BoardH);
      AddLog(G, 'A final flicker is swallowed by darkness.');
      RemoveOneFlickerTile := True;
      Exit;
    end;
  end;
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
begin
  RemainingKeys := CountHeldKeys(G) + CountBoardFeature(G, ftKey) + G.FeatureKeys;
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
