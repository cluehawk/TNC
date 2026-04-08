unit TNCRule;

interface

uses
  TNCDef,
  TNCGen;

procedure RebuildOccupancy(var G: TGameState);
procedure ResolveRelights(var G: TGameState);
procedure RecomputeLighting(var G: TGameState);
function CanMoveDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function MovePrisoner(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function StayPrisoner(var G: TGameState; Index: Byte): Boolean;
function HasAnyReEntry(const G: TGameState; Index: Byte): Boolean;
function CanReEnterDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function ResolveFallingEntry(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
function CountMonsterSightings(const G: TGameState; Index: Byte): Byte;
function WaxEscapeVictimMask(const G: TGameState; ActiveIndex, OldX, OldY: Byte): Byte;
function WaxContactVictimMask(const G: TGameState; Index: Byte): Byte;
procedure ApplyMonsterHit(var G: TGameState; Index: Byte; Count: Byte; Brace: Boolean);
procedure CollapseDarkness(var G: TGameState);
function RemoveOneFlickerTile(var G: TGameState): Boolean;
procedure CheckPhaseTransitions(var G: TGameState);
procedure CheckWinLoss(var G: TGameState);
function PrisonerCanAct(const G: TGameState; Index: Byte): Boolean;

implementation

procedure RebuildOccupancy(var G: TGameState);
var
  X, Y, I: Byte;
begin
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      G.Board[X, Y].Flags := G.Board[X, Y].Flags - [cfOccupied];

  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].Alive and (not G.Prisoners[I].Falling) then
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
      if Q.Alive and Q.Lit and (not Q.Falling) then
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
    if G.Prisoners[I].Alive and (not G.Prisoners[I].Falling) and (not G.Prisoners[I].Lit) then
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
begin
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      G.Board[X, Y].Flags := G.Board[X, Y].Flags - [cfLit];

  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].Alive and G.Prisoners[I].Lit and (not G.Prisoners[I].Falling) then
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
          if CellOpen(G.Board[X, Y], D) then
          begin
            if (not IsPresent(G.Board[NX, NY])) and (G.Phase = gpMaze) and (G.DrawsRemaining > 0) then
              GenerateCell(G, NX, NY);
          end;
          if IsPresent(G.Board[NX, NY]) then
          begin
            G.Board[NX, NY].Flags := G.Board[NX, NY].Flags + [cfLit];
            G.Board[NX, NY].LastLitTurn := G.TurnNumber;
          end;
        end;
      end;
    end;
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
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) then
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
    if G.Prisoners[Index].Lit and CanGenerateCell(G, NX, NY) then
      CanMoveDirection := True;
    Exit;
  end;

  if IsPitCell(G.Board[NX, NY]) then
    CanMoveDirection := True
  else if IsPassable(G.Board[NX, NY]) and CellOpen(G.Board[NX, NY], OppositeDir(Dir)) then
    CanMoveDirection := True;
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
    if not GenerateCell(G, NX, NY) then
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
    G.Prisoners[Index].Lit := False;
    AddLog(G, PrisonerName(Index) + ' leaps into a pit and falls.');
    MovePrisoner := True;
    Exit;
  end;

  if not IsPassable(G.Board[NX, NY]) then
    Exit;

  AddLog(G, PrisonerName(Index) + ' moves ' + DirName(Dir) + '.');
  HandleEntryFeature(G, Index);
  MovePrisoner := True;
end;

function StayPrisoner(var G: TGameState; Index: Byte): Boolean;
var
  X, Y: Byte;
begin
  StayPrisoner := False;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) then
    Exit;

  if not G.Prisoners[Index].Lit then
  begin
    if G.Prisoners[Index].Nerve = 0 then
      Exit;
    Dec(G.Prisoners[Index].Nerve);
    AddLog(G, PrisonerName(Index) + ' spends 1 nerve to hold still in darkness.');
  end;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  AddLog(G, PrisonerName(Index) + ' stays put.');

  if IsPitCell(G.Board[X, Y]) then
  begin
    G.Prisoners[Index].Falling := True;
    G.Prisoners[Index].Lit := False;
    AddLog(G, PrisonerName(Index) + ' falls from the pit.');
    StayPrisoner := True;
    Exit;
  end;

  if TileBreaksOnUse(G.Board[X, Y]) then
  begin
    ConvertToPit(G.Board[X, Y]);
    G.Prisoners[Index].Falling := True;
    G.Prisoners[Index].Lit := False;
    AddLog(G, PrisonerName(Index) + ' falls as the tile gives way.');
  end;

  StayPrisoner := True;
end;

function FindReEntry(const G: TGameState; Index: Byte; Dir: TDirection; var TX, TY: Byte): Boolean;
var
  Step, SX, SY: Byte;
begin
  FindReEntry := False;
  case Dir of
    dirNorth:
      begin
        SX := G.Prisoners[Index].X;
        for Step := 0 to BoardH - 1 do
        begin
          TX := SX;
          TY := Step;
          if IsPassable(G.Board[TX, TY]) and CellOpen(G.Board[TX, TY], dirNorth) then
          begin
            FindReEntry := True;
            Exit;
          end;
        end;
      end;
    dirSouth:
      begin
        SX := G.Prisoners[Index].X;
        for Step := 0 to BoardH - 1 do
        begin
          TX := SX;
          TY := BoardH - 1 - Step;
          if IsPassable(G.Board[TX, TY]) and CellOpen(G.Board[TX, TY], dirSouth) then
          begin
            FindReEntry := True;
            Exit;
          end;
        end;
      end;
    dirWest:
      begin
        SY := G.Prisoners[Index].Y;
        for Step := 0 to BoardW - 1 do
        begin
          TX := Step;
          TY := SY;
          if IsPassable(G.Board[TX, TY]) and CellOpen(G.Board[TX, TY], dirWest) then
          begin
            FindReEntry := True;
            Exit;
          end;
        end;
      end;
    dirEast:
      begin
        SY := G.Prisoners[Index].Y;
        for Step := 0 to BoardW - 1 do
        begin
          TX := BoardW - 1 - Step;
          TY := SY;
          if IsPassable(G.Board[TX, TY]) and CellOpen(G.Board[TX, TY], dirEast) then
          begin
            FindReEntry := True;
            Exit;
          end;
        end;
      end;
  end;
end;

function HasAnyReEntry(const G: TGameState; Index: Byte): Boolean;
var
  Dir: TDirection;
  TX, TY: Byte;
begin
  HasAnyReEntry := False;
  for Dir := dirNorth to dirWest do
    if FindReEntry(G, Index, Dir, TX, TY) then
    begin
      HasAnyReEntry := True;
      Exit;
    end;
end;

function CanReEnterDirection(const G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  TX, TY: Byte;
begin
  CanReEnterDirection := FindReEntry(G, Index, Dir, TX, TY);
end;

function ResolveFallingEntry(var G: TGameState; Index: Byte; Dir: TDirection): Boolean;
var
  TX, TY: Byte;
begin
  ResolveFallingEntry := False;
  if not G.Prisoners[Index].Falling then
    Exit;
  if not FindReEntry(G, Index, Dir, TX, TY) then
    Exit;

  G.Prisoners[Index].X := TX;
  G.Prisoners[Index].Y := TY;
  G.Prisoners[Index].Falling := False;
  G.Prisoners[Index].Lit := False;
  AddLog(G, PrisonerName(Index) + ' re-enters from the ' + DirName(Dir) + '.');
  HandleEntryFeature(G, Index);
  ResolveFallingEntry := True;
end;

function RayMonsterCount(const G: TGameState; X, Y: Byte; Dir: TDirection): Byte;
var
  CX, CY, NX, NY, Limit, Step: Byte;
  Count: Byte;
begin
  RayMonsterCount := 0;
  Count := 0;
  CX := X;
  CY := Y;
  if (Dir = dirNorth) or (Dir = dirSouth) then
    Limit := BoardH
  else
    Limit := BoardW;

  for Step := 1 to Limit do
  begin
    if (not IsPresent(G.Board[CX, CY])) or (not CellOpen(G.Board[CX, CY], Dir)) then
    begin
      RayMonsterCount := Count;
      Exit;
    end;

    NX := WrapX(Integer(CX) + DirX[Dir]);
    NY := WrapY(Integer(CY) + DirY[Dir]);
    if (not IsPresent(G.Board[NX, NY])) or (G.Board[NX, NY].Kind = tkPit) then
    begin
      RayMonsterCount := Count;
      Exit;
    end;
    if not CellOpen(G.Board[NX, NY], OppositeDir(Dir)) then
    begin
      RayMonsterCount := Count;
      Exit;
    end;

    CX := NX;
    CY := NY;
    if G.Board[CX, CY].Feature = ftMonster then
      Inc(Count);
  end;
  RayMonsterCount := Count;
end;

function CountMonsterSightings(const G: TGameState; Index: Byte): Byte;
var
  D: TDirection;
  Count: Byte;
begin
  Count := 0;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) then
  begin
    CountMonsterSightings := 0;
    Exit;
  end;
  for D := dirNorth to dirWest do
    Inc(Count, RayMonsterCount(G, G.Prisoners[Index].X, G.Prisoners[Index].Y, D));
  CountMonsterSightings := Count;
end;

function MonsterSeesCell(const G: TGameState; MX, MY, TX, TY: Byte; var HitDir: TDirection): Boolean;
var
  D: TDirection;
  CX, CY, NX, NY, Limit, Step: Byte;
  Blocked: Boolean;
begin
  MonsterSeesCell := False;
  for D := dirNorth to dirWest do
  begin
    CX := MX;
    CY := MY;
    if (D = dirNorth) or (D = dirSouth) then
      Limit := BoardH
    else
      Limit := BoardW;

    Step := 0;
    Blocked := False;
    while (Step < Limit) and (not Blocked) do
    begin
      Inc(Step);
      if (not IsPresent(G.Board[CX, CY])) or (not CellOpen(G.Board[CX, CY], D)) then
        Blocked := True
      else
      begin
        NX := WrapX(Integer(CX) + DirX[D]);
        NY := WrapY(Integer(CY) + DirY[D]);
        if (NX = TX) and (NY = TY) then
        begin
          HitDir := D;
          MonsterSeesCell := True;
          Exit;
        end;
        if (not IsPresent(G.Board[NX, NY])) or (G.Board[NX, NY].Kind = tkPit) then
          Blocked := True
        else if not CellOpen(G.Board[NX, NY], OppositeDir(D)) then
          Blocked := True
        else
        begin
          CX := NX;
          CY := NY;
        end;
      end;
    end;
  end;
end;

function PrisonerAtCell(const G: TGameState; X, Y: Byte): Byte;
var
  I: Byte;
begin
  PrisonerAtCell := PrisonerCount;
  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].Alive and (not G.Prisoners[I].Falling) and
       (G.Prisoners[I].X = X) and (G.Prisoners[I].Y = Y) then
    begin
      PrisonerAtCell := I;
      Exit;
    end;
end;

function FirstVictimOnRay(const G: TGameState; MX, MY: Byte; D: TDirection): Byte;
var
  CX, CY, NX, NY, Limit, Step, Victim: Byte;
begin
  FirstVictimOnRay := PrisonerCount;
  CX := MX;
  CY := MY;
  if (D = dirNorth) or (D = dirSouth) then
    Limit := BoardH
  else
    Limit := BoardW;

  for Step := 1 to Limit do
  begin
    if (not IsPresent(G.Board[CX, CY])) or (not CellOpen(G.Board[CX, CY], D)) then
      Exit;
    NX := WrapX(Integer(CX) + DirX[D]);
    NY := WrapY(Integer(CY) + DirY[D]);
    if (not IsPresent(G.Board[NX, NY])) or (G.Board[NX, NY].Kind = tkPit) then
      Exit;
    if not CellOpen(G.Board[NX, NY], OppositeDir(D)) then
      Exit;

    Victim := PrisonerAtCell(G, NX, NY);
    if Victim < PrisonerCount then
    begin
      FirstVictimOnRay := Victim;
      Exit;
    end;

    CX := NX;
    CY := NY;
  end;
end;

function WaxEscapeVictimMask(const G: TGameState; ActiveIndex, OldX, OldY: Byte): Byte;
var
  X, Y, Victim: Byte;
  Mask: Byte;
  OldDir, NewDir: TDirection;
begin
  Mask := 0;
  for X := 0 to BoardW - 1 do
    for Y := 0 to BoardH - 1 do
      if IsPresent(G.Board[X, Y]) and (G.Board[X, Y].Feature = ftMonster) then
        if MonsterSeesCell(G, X, Y, OldX, OldY, OldDir) and
           (not MonsterSeesCell(G, X, Y, G.Prisoners[ActiveIndex].X, G.Prisoners[ActiveIndex].Y, NewDir)) then
        begin
          Victim := FirstVictimOnRay(G, X, Y, OldDir);
          if Victim < PrisonerCount then
            Mask := Mask or (1 shl Victim);
        end;
  WaxEscapeVictimMask := Mask;
end;

function WaxContactVictimMask(const G: TGameState; Index: Byte): Byte;
var
  X, Y: Byte;
begin
  WaxContactVictimMask := 0;
  if G.Prisoners[Index].Falling or (not G.Prisoners[Index].Alive) then
    Exit;

  X := G.Prisoners[Index].X;
  Y := G.Prisoners[Index].Y;
  if IsPresent(G.Board[X, Y]) and (G.Board[X, Y].Kind <> tkPit) and
     (G.Board[X, Y].Feature = ftMonster) then
    WaxContactVictimMask := 1 shl Index;
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
    Loss := Count;
    AddLog(G, PrisonerName(Index) + ' braces against the dark with nerve.');
  end
  else
    Loss := Count + 1;

  G.Prisoners[Index].Lit := False;
  DiscardDrawTiles(G, Loss);
  AddLog(G, PrisonerName(Index) + ' is struck by wax eaters.');
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

function AllOnSameGate(const G: TGameState): Boolean;
var
  I: Byte;
  GX, GY: Byte;
begin
  AllOnSameGate := False;
  if G.Prisoners[0].Falling then
    Exit;
  GX := G.Prisoners[0].X;
  GY := G.Prisoners[0].Y;
  if not IsPresent(G.Board[GX, GY]) then
    Exit;
  if G.Board[GX, GY].Feature <> ftGate then
    Exit;

  for I := 1 to PrisonerCount - 1 do
    if G.Prisoners[I].Falling or
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

  TotalKeyCapacity := CountHeldKeys(G) + CountBoardFeature(G, ftKey) + G.FeatureKeys;
  if TotalKeyCapacity < 4 then
  begin
    G.Phase := gpLoss;
    AddLog(G, 'Too many keys are gone. Escape is impossible.');
    Exit;
  end;

  GateCapacity := CountBoardFeature(G, ftGate);
  if G.Phase = gpMaze then
    Inc(GateCapacity, G.FeatureGates);
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
