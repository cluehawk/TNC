{============================================================================}
{  CAGE OF SHADOWS - A Text-Mode DOS Survival Game                           }
{  Compatible with IBM PC/XT (8088), Turbo Pascal 7.0                        }
{  Target: 80x25 CGA/MDA text mode, ~4KB executable                          }
{============================================================================}

PROGRAM CageOfShadows;

USES Crt;

{============================================================================}
{ CONSTANTS                                                                 }
{============================================================================}

CONST
  BOARD_WIDTH   = 12;
  BOARD_HEIGHT  = 8;
  MAX_PRISONERS = 4;
  DRAW_STACK_SIZE = 40;
  MAX_NERVE     = 3;
  
  {Tile types}
  ttDark        = 0;
  ttPassage     = 1;
  ttCorner      = 2;
  ttTJunction   = 3;
  ttCross       = 4;
  ttKey         = 5;
  ttGate        = 6;
  ttCrumbling   = 7;
  ttPit         = 8;
  ttMonster     = 9;

  {Directions}
  dirNorth      = 0;
  dirSouth      = 1;
  dirEast       = 2;
  dirWest       = 3;

{============================================================================}
{ TYPE DEFINITIONS                                                          }
{============================================================================}

TYPE
  Connections = SET OF 0..3; {dirNorth, dirSouth, dirEast, dirWest}

  TTile = RECORD
    tileType: BYTE;
    connections: Connections;
    hasKey: BOOLEAN;
    isGate: BOOLEAN;
    isCrumbling: BOOLEAN;
    monsterPresent: BOOLEAN;
    litByPrisoner: BYTE; {0=none, 1-4=prisoner ID}
  END;

  TPrisonerState = (psNormal, psLightsOut, psFalling, psDead);

  TPrisoner = RECORD
    id: BYTE;
    name: STRING[12];
    x, y: INTEGER;
    isLit: BOOLEAN;
    hasKey: BOOLEAN;
    nerve: BYTE;
    maxNerve: BYTE;
    state: TPrisonerState;
  END;

{============================================================================}
{ GLOBAL VARIABLES                                                          }
{============================================================================}

VAR
  board: ARRAY[0..BOARD_WIDTH-1, 0..BOARD_HEIGHT-1] OF TTile;
  prisoners: ARRAY[1..MAX_PRISONERS] OF TPrisoner;
  
  activePrisoner: BYTE;
  turnNumber: INTEGER;
  drawStack: INTEGER;
  finalFlickers: BOOLEAN;
  
  messageLog: ARRAY[0..2] OF STRING[60];
  logIndex: BYTE;

{============================================================================}
{ UTILITY FUNCTIONS                                                         }
{============================================================================}

FUNCTION WrapX(x: INTEGER): INTEGER;
BEGIN
  IF x < 0 THEN x := BOARD_WIDTH - 1 + ((x MOD BOARD_WIDTH) + BOARD_WIDTH);
  IF x >= BOARD_WIDTH THEN x := x MOD BOARD_WIDTH;
  WrapX := x;
END;

FUNCTION WrapY(y: INTEGER): INTEGER;
BEGIN
  IF y < 0 THEN y := BOARD_HEIGHT - 1 + ((y MOD BOARD_HEIGHT) + BOARD_HEIGHT);
  IF y >= BOARD_HEIGHT THEN y := y MOD BOARD_HEIGHT;
  WrapY := y;
END;

PROCEDURE LogMessage(msg: STRING);
BEGIN
  messageLog[logIndex] := msg;
  logIndex := (logIndex + 1) MOD 3;
END;

{============================================================================}
{ TILE GENERATION                                                           }
{============================================================================}

PROCEDURE GenerateTile(VAR t: TTile);
VAR
  roll: INTEGER;
BEGIN
  {Initialize tile as dark/unexplored}
  t.tileType := ttDark;
  t.connections := [];
  t.hasKey := FALSE;
  t.isGate := FALSE;
  t.isCrumbling := FALSE;
  t.monsterPresent := FALSE;
  t.litByPrisoner := 0;

  IF drawStack <= 0 THEN EXIT; {No more tiles in Final Flickers}

  roll := Random(100) + 1;

  {Determine passage type based on weighted random}
  IF roll <= 35 THEN
    t.tileType := ttPassage
  ELSE IF roll <= 60 THEN
    t.tileType := ttCorner
  ELSE IF roll <= 80 THEN
    t.tileType := ttTJunction
  ELSE IF roll <= 90 THEN
    t.tileType := ttCross
  ELSE
  BEGIN
    {Special tile - weighted selection}
    roll := Random(10) + 1;
    CASE roll OF
      1,2: BEGIN t.tileType := ttKey; t.hasKey := TRUE; END;
      3,4: BEGIN t.tileType := ttGate; t.isGate := TRUE; END;
      5:   BEGIN t.tileType := ttCrumbling; t.isCrumbling := TRUE; END;
      6..10: BEGIN t.tileType := ttMonster; t.monsterPresent := TRUE; END;
    END;
  END;

  {Set connections based on type}
  CASE t.tileType OF
    ttPassage: t.connections := [dirNorth, dirSouth];
    ttCorner: t.connections := [dirNorth, dirEast];
    ttTJunction: t.connections := [dirNorth, dirSouth, dirEast];
    ttCross: t.connections := [dirNorth, dirSouth, dirEast, dirWest];
  END;

  {Special tiles inherit passage connections}
  IF (t.tileType >= ttKey) AND (t.tileType <= ttMonster) THEN
    t.connections := [dirNorth, dirSouth, dirEast, dirWest];

  drawStack := drawStack - 1;
END;

{============================================================================}
{ ILLUMINATION SYSTEM                                                       }
{============================================================================}

PROCEDURE CalculateIllumination;
VAR
  pId: BYTE;
  x, y, nx, ny: INTEGER;
  d: BYTE;
BEGIN
  {Clear all illumination}
  FOR x := 0 TO BOARD_WIDTH-1 DO
    FOR y := 0 TO BOARD_HEIGHT-1 DO
      board[x,y].litByPrisoner := 0;

  {For each prisoner, illuminate reachable tiles}
  FOR pId := 1 TO MAX_PRISONERS DO
  BEGIN
    IF prisoners[pId].state = psDead THEN CONTINUE;

    x := prisoners[pId].x;
    y := prisoners[pId].y;

    {Always light current tile}
    board[x,y].litByPrisoner := pId;

    IF NOT prisoners[pId].isLit THEN CONTINUE; {Lights out = no spread}

    {Light connected adjacent tiles (radius 1)}
    FOR d := dirNorth TO dirWest DO
      IF d IN board[x,y].connections THEN
      BEGIN
        CASE d OF
          dirNorth: BEGIN nx := x; ny := y - 1; END;
          dirSouth: BEGIN nx := x; ny := y + 1; END;
          dirEast:  BEGIN nx := x + 1; ny := y; END;
          dirWest:  BEGIN nx := x - 1; ny := y; END;
        END;

        nx := WrapX(nx);
        ny := WrapY(ny);

        board[nx,ny].litByPrisoner := pId;
      END;
  END;
END;

PROCEDURE RemoveUnlitTiles;
VAR
  x, y: INTEGER;
BEGIN
  FOR x := 0 TO BOARD_WIDTH-1 DO
    FOR y := 0 TO BOARD_HEIGHT-1 DO
    BEGIN
      IF board[x,y].litByPrisoner = 0 THEN
      BEGIN
        {Tile goes dark - check if prisoner is on it}
        IF (board[x,y].tileType <> ttPit) AND (board[x,y].tileType <> ttDark) THEN
        BEGIN
          {Check for prisoners on this tile}
          FOR pId := 1 TO MAX_PRISONERS DO
            IF (prisoners[pId].x = x) AND (prisoners[pId].y = y) THEN
              prisoners[pId].isLit := FALSE;

          board[x,y].tileType := ttDark;
        END;
      END;
    END;
END;

PROCEDURE GenerateNewTiles;
VAR
  x, y: INTEGER;
BEGIN
  FOR x := 0 TO BOARD_WIDTH-1 DO
    FOR y := 0 TO BOARD_HEIGHT-1 DO
    BEGIN
      IF (board[x,y].tileType = ttDark) AND (board[x,y].litByPrisoner > 0) THEN
        GenerateTile(board[x,y]);
    END;
END;

{============================================================================}
{ MONSTER ATTACKS                                                           }
{============================================================================}

FUNCTION GetDirection(dx, dy: INTEGER): BYTE;
BEGIN
  IF dx = 0 THEN
    IF dy < 0 THEN GetDirection := dirNorth ELSE GetDirection := dirSouth
  ELSE
    IF dx > 0 THEN GetDirection := dirEast ELSE GetDirection := dirWest;
END;

PROCEDURE ProcessMonsterAttacks(prisonerId: BYTE);
VAR
  px, py, mx, my: INTEGER;
  d: BYTE;
  hitPrisoners: SET OF 1..4;
  tx, ty: INTEGER;
  pId: BYTE;
BEGIN
  hitPrisoners := [];

  {Find all monsters on board}
  FOR mx := 0 TO BOARD_WIDTH-1 DO
    FOR my := 0 TO BOARD_HEIGHT-1 DO
      IF board[mx,my].monsterPresent THEN
      BEGIN
        px := prisoners[prisonerId].x;
        py := prisoners[prisonerId].y;

        {Check if prisoner is in line of sight (same row or column)}
        IF (px = mx) OR (py = my) THEN
        BEGIN
          {Determine direction from monster to prisoner}
          d := GetDirection(px - mx, py - my);

          {Propagate attack through connected passages}
          tx := mx;
          ty := my;

          REPEAT
            CASE d OF
              dirNorth: ty := WrapY(ty - 1);
              dirSouth: ty := WrapY(ty + 1);
              dirEast:  tx := WrapX(tx + 1);
              dirWest:  tx := WrapX(tx - 1);
            END;

            {Check if path is blocked}
            IF (board[tx,ty].tileType = ttPit) OR (board[tx,ty].tileType = ttDark) THEN
              BREAK;

            {Check for prisoners in path}
            FOR pId := 1 TO MAX_PRISONERS DO
            BEGIN  { <-- ADDED }
              IF (prisoners[pId].x = tx) AND (prisoners[pId].y = ty) THEN
                hitPrisoners := hitPrisoners + [pId];
            END;   { <-- ADDED }

          UNTIL ((tx = px) AND (ty = py)) OR (drawStack <= 0);
        END;
      END;

  {Apply damage to hit prisoners}
  FOR pId := 1 TO MAX_PRISONERS DO
    IF pId IN hitPrisoners THEN
    BEGIN
      IF prisoners[pId].state <> psDead THEN
      BEGIN
        prisoners[pId].isLit := FALSE;
        prisoners[pId].state := psLightsOut;

        {Spend nerve to reduce damage if available}
        IF (prisoners[pId].nerve >= 2) AND (drawStack > 0) THEN
        BEGIN
          prisoners[pId].nerve := prisoners[pId].nerve - 2;
          LogMessage(prisoners[pId].name + ' uses Brave Heart!');
        END
        ELSE
        BEGIN
          drawStack := drawStack - 1;
          IF drawStack < 0 THEN drawStack := 0;
        END;

        LogMessage('Monster attacks ' + prisoners[pId].name + '! Lights out!');
      END;
    END;
END;

{============================================================================}
{ MOVEMENT AND ACTIONS                                                      }
{============================================================================}

FUNCTION CanMoveTo(x, y: INTEGER): BOOLEAN;
BEGIN
  IF (board[x,y].tileType = ttPit) OR (board[x,y].tileType = ttDark) THEN
    CanMoveTo := FALSE
  ELSE
    CanMoveTo := TRUE;
END;

PROCEDURE MovePrisoner(prisonerId: BYTE, direction: BYTE);
VAR
  px, py, nx, ny: INTEGER;
BEGIN
  px := prisoners[prisonerId].x;
  py := prisoners[prisonerId].y;

  CASE direction OF
    dirNorth: BEGIN nx := px; ny := WrapY(py - 1); END;
    dirSouth: BEGIN nx := px; ny := WrapY(py + 1); END;
    dirEast:  BEGIN nx := WrapX(px + 1); ny := py; END;
    dirWest:  BEGIN nx := WrapX(px - 1); ny := py; END;
  END;

  {Check if movement is valid}
  IF NOT CanMoveTo(nx, ny) THEN
  BEGIN
    LogMessage('Cannot move there!');
    EXIT;
  END;

  {Check connection from current tile}
  IF direction IN board[px,py].connections THEN
  BEGIN
    {Execute movement}
    prisoners[prisonerId].x := nx;
    prisoners[prisonerId].y := ny;

    {Handle special tiles}
    CASE board[nx,ny].tileType OF
      ttKey:
        IF NOT prisoners[prisonerId].hasKey THEN
        BEGIN
          prisoners[prisoners[prisonerId]].hasKey := TRUE;
          board[nx,ny].hasKey := FALSE;
          LogMessage(prisoners[prisonerId].name + ' picks up a KEY!');
        END;

      ttCrumbling:
        IF board[nx,ny].isCrumbling THEN
        BEGIN
          {Check if prisoner has nerve to hold light}
          IF (prisoners[prisonerId].nerve >= 1) AND 
             (ReadKey = #0) AND (ReadKey = 'N') THEN
          BEGIN
            prisoners[prisonerId].nerve := prisoners[prisonerId].nerve - 1;
            LogMessage(prisoners[prisonerId].name + ' holds light on crumbling tile!');
          END
          ELSE
          BEGIN
            {Tile becomes pit}
            board[nx,ny].tileType := ttPit;
            prisoners[prisonerId].state := psFalling;
            LogMessage(prisoners[prisonerId].name + ' falls into the darkness!');
          END;
        END;
    END;

    {Check for monster attacks}
    ProcessMonsterAttacks(prisonerId);
  END
  ELSE
    LogMessage('No passage in that direction!');
END;

PROCEDURE StayPrisoner(prisonerId: BYTE);
VAR
  px, py: INTEGER;
BEGIN
  px := prisoners[prisonerId].x;
  py := prisoners[prisonerId].y;

  {Check if on crumbling tile}
  IF board[px,py].isCrumbling THEN
  BEGIN
    IF (prisoners[prisonerId].nerve >= 1) THEN
    BEGIN
      prisoners[prisonerId].nerve := prisoners[prisonerId].nerve - 1;
      LogMessage(prisoners[prisonerId].name + ' holds light while staying!');
    END
    ELSE
    BEGIN
      board[px,py].tileType := ttPit;
      prisoners[prisonerId].state := psFalling;
      LogMessage(prisoners[prisonerId].name + ' falls while staying on crumbling tile!');
    END;
  END
  ELSE
    LogMessage(prisoners[prisonerId].name + ' stays put.');
END;

PROCEDURE SpendNerve(prisonerId: BYTE);
BEGIN
  IF prisoners[prisonerId].nerve > 0 THEN
  BEGIN
    prisoners[prisonerId].nerve := prisoners[prisonerId].nerve - 1;
    
    {Second Wind - move again}
    LogMessage(prisoners[prisonerId].name + ' spends nerve for Second Wind!');
    activePrisoner := prisonerId; {Stay on same prisoner}
  END
  ELSE
    LogMessage('No nerve available!');
END;

{============================================================================}
{ RELIGHTING MECHANIC                                                       }
{============================================================================}

PROCEDURE CheckRelighting;
VAR
  p1, p2: BYTE;
  px1, py1, px2, py2: INTEGER;
BEGIN
  FOR p1 := 1 TO MAX_PRISONERS DO
    IF (prisoners[p1].state = psLightsOut) AND prisoners[p1].isLit THEN
    BEGIN
      {Check adjacency to lit prisoner}
      FOR p2 := 1 TO MAX_PRISONERS DO
        IF p1 <> p2 THEN
        BEGIN
          px1 := prisoners[p1].x;
          py1 := prisoners[p1].y;
          px2 := prisoners[p2].x;
          py2 := prisoners[p2].y;

          {Check if adjacent (including wrapping)}
          IF ((px1 = px2) OR (Abs(px1 - px2) = 1)) AND 
             ((py1 = py2) OR (Abs(py1 - py2) = 1)) THEN
          BEGIN
            prisoners[p1].isLit := TRUE;
            prisoners[p1].state := psNormal;
            LogMessage(prisoners[p1].name + ' is relit by ' + prisoners[p2].name + '!');
            BREAK;
          END;
        END;
    END;
END;

{============================================================================}
{ FALLING RE-ENTRY                                                          }
{============================================================================}

PROCEDURE HandleFallingPrisoners;
VAR
  pId: BYTE;
  rx, ry: INTEGER;
  attempts: INTEGER;
BEGIN
  FOR pId := 1 TO MAX_PRISONERS DO
    IF prisoners[pId].state = psFalling THEN
    BEGIN
      {Try to find valid landing spot on same row or column}
      attempts := 0;
      REPEAT
        rx := Random(BOARD_WIDTH);
        ry := Random(BOARD_HEIGHT);

        {Prefer same row or column as original position}
        IF (attempts MOD 2 = 0) THEN
          rx := prisoners[pId].x
        ELSE
          ry := prisoners[pId].y;

        attempts := attempts + 1;
      UNTIL CanMoveTo(rx, ry) OR (attempts > 50);

      IF CanMoveTo(rx, ry) THEN
      BEGIN
        prisoners[pId].x := rx;
        prisoners[pId].y := ry;
        prisoners[pId].state := psNormal;
        prisoners[pId].isLit := TRUE;
        LogMessage(prisoners[pId].name + ' emerges from the darkness!');
      END
      ELSE
      BEGIN
        prisoners[pId].state := psDead;
        LogMessage(prisoners[pId].name + ' is lost forever...');
      END;
    END;
END;

{============================================================================}
{ WIN/LOSS CONDITIONS                                                       }
{============================================================================}

FUNCTION CheckWinCondition: BOOLEAN;
VAR
  p1, p2: BYTE;
  gateFound: BOOLEAN;
BEGIN
  {Check if all prisoners are at same gate with keys}
  IF (prisoners[1].state = psDead) OR (prisoners[2].state = psDead) OR
     (prisoners[3].state = psDead) OR (prisoners[4].state = psDead) THEN
  BEGIN
    CheckWinCondition := FALSE;
    EXIT;
  END;

  {Check if all have keys}
  IF NOT (prisoners[1].hasKey AND prisoners[2].hasKey AND 
          prisoners[3].hasKey AND prisoners[4].hasKey) THEN
  BEGIN
    CheckWinCondition := FALSE;
    EXIT;
  END;

  {Check if all at same position}
  IF NOT ((prisoners[1].x = prisoners[2].x) AND (prisoners[1].y = prisoners[2].y) AND
          (prisoners[1].x = prisoners[3].x) AND (prisoners[1].y = prisoners[3].y) AND
          (prisoners[1].x = prisoners[4].x) AND (prisoners[1].y = prisoners[4].y)) THEN
  BEGIN
    CheckWinCondition := FALSE;
    EXIT;
  END;

  {Check if at a gate}
  IF board[prisoners[1].x, prisoners[1].y].isGate THEN
    CheckWinCondition := TRUE
  ELSE
    CheckWinCondition := FALSE;
END;

FUNCTION CheckLossCondition: BOOLEAN;
VAR
  deadCount: BYTE;
BEGIN
  {Count dead prisoners}
  deadCount := 0;
  FOR pId := 1 TO MAX_PRISONERS DO
    IF prisoners[pId].state = psDead THEN
      deadCount := deadCount + 1;

  {Loss if all prisoners dead or permanently lights out}
  IF deadCount >= 4 THEN
  BEGIN
    CheckLossCondition := TRUE;
    EXIT;
  END;

  {Loss if draw stack exhausted and no gates remain}
  IF (drawStack <= 0) AND finalFlickers THEN
  BEGIN
    {Check for remaining gates}
    FOR x := 0 TO BOARD_WIDTH-1 DO
      FOR y := 0 TO BOARD_HEIGHT-1 DO
        IF board[x,y].isGate THEN
        BEGIN
          CheckLossCondition := FALSE;
          EXIT;
        END;

    CheckLossCondition := TRUE;
  END
  ELSE
    CheckLossCondition := FALSE;
END;

{============================================================================}
{ UI RENDERING                                                              }
{============================================================================}

PROCEDURE DrawBoard;
VAR
  x, y: INTEGER;
  ch: CHAR;
BEGIN
  GotoXY(1, 3);

  FOR y := 0 TO BOARD_HEIGHT-1 DO
  BEGIN
    FOR x := 0 TO BOARD_WIDTH-1 DO
    BEGIN
      {Determine character to display}
      CASE board[x,y].tileType OF
        ttDark: ch := '.';
        ttPassage, ttCorner, ttTJunction, ttCross: ch := '+';
        ttKey: IF board[x,y].hasKey THEN ch := 'K' ELSE ch := '+';
        ttGate: ch := 'G';
        ttCrumbling: ch := '~';
        ttPit: ch := '#';
        ttMonster: ch := 'M';
      END;

      {Check if lit}
      IF board[x,y].litByPrisoner = 0 THEN
        ch := '.';

      {Check for prisoners on tile}
      FOR pId := 1 TO MAX_PRISONERS DO
        IF (prisoners[pId].x = x) AND (prisoners[pId].y = y) THEN
        BEGIN
          IF prisoners[pId].id = activePrisoner THEN
            ch := '@'
          ELSE
            ch := '*';

          {Lights out indicator}
          IF NOT prisoners[pId].isLit THEN
            ch := 'o';
        END;

      Write(ch);
    END;
    Write(#13#10);
  END;
END;

PROCEDURE DrawStatusPanel;
VAR
  pId: BYTE;
BEGIN
  GotoXY(1, 12);
  Write('ACTIVE: ');

  FOR pId := 1 TO MAX_PRISONERS DO
  BEGIN
    IF pId = activePrisoner THEN
      TextColor(Yellow)
    ELSE
      TextColor(White);

    Write('[', pId, '] ', prisoners[pId].name[1..8]);

    {Lit status}
    IF prisoners[pId].isLit THEN
      Write('● Lit')
    ELSE
      Write('○ Out');

    {Key status}
    IF prisoners[pId].hasKey THEN
      Write(' Key: YES')
    ELSE
      Write(' Key: NO ');

    {Nerve count}
    Write(' Nerve: ', prisoners[pId].nerve, '/', prisoners[pId].maxNerve);

    TextColor(White);
    Write(#13#10);
  END;
END;

PROCEDURE DrawHeader;
BEGIN
  GotoXY(1, 1);
  TextBackground(Blue);
  TextColor(Yellow);
  Write(' CAGE OF SHADOWS - Turn: ', turnNumber:2, '    Stack: ', drawStack:2, '/', DRAW_STACK_SIZE);
  
  IF finalFlickers THEN
    Write('    *** FINAL FLICKERS ***')
  ELSE
    Write('    Flickers: NO');

  TextBackground(Black);
  TextColor(White);
END;

PROCEDURE DrawMessageLog;
VAR
  i: BYTE;
BEGIN
  GotoXY(1, 18);
  FOR i := 0 TO 2 DO
  BEGIN
    Write(messageLog[(logIndex + i) MOD 3]);
    IF i < 2 THEN Write(#13#10);
  END;
END;

PROCEDURE DrawControls;
BEGIN
  GotoXY(1, 20);
  Write('Controls: Arrows=Move  S=Stay  N=Spend Nerve  Q=Quit');

  GotoXY(1, 21);
  Write('Legend: @=You  *=Other  o=LightsOut  .=Dark  +=Passage  K=Key  G=Gate  M=Monster');
END;

PROCEDURE ClearScreen;
BEGIN
  ClrScr;
  DrawHeader;
  DrawBoard;
  DrawStatusPanel;
  DrawMessageLog;
  DrawControls;
END;

{============================================================================}
{ GAME INITIALIZATION                                                       }
{============================================================================}

PROCEDURE InitializeGame;
VAR
  pId: BYTE;
BEGIN
  {Initialize random seed}
  Randomize;

  {Reset game state}
  turnNumber := 0;
  drawStack := DRAW_STACK_SIZE;
  finalFlickers := FALSE;
  activePrisoner := 1;
  logIndex := 0;

  {Initialize prisoners}
  prisoners[1].id := 1; prisoners[1].name := 'ALEXANDER';
  prisoners[2].id := 2; prisoners[2].name := 'BENJAMIN';
  prisoners[3].id := 3; prisoners[3].name := 'CATHERINE';
  prisoners[4].id := 4; prisoners[4].name := 'DAVID';

  FOR pId := 1 TO MAX_PRISONERS DO
  BEGIN
    prisoners[pId].x := Random(BOARD_WIDTH);
    prisoners[pId].y := Random(BOARD_HEIGHT);
    prisoners[pId].isLit := TRUE;
    prisoners[pId].hasKey := FALSE;
    prisoners[pId].nerve := MAX_NERVE;
    prisoners[pId].maxNerve := MAX_NERVE;
    prisoners[pId].state := psNormal;
  END;

  {Initialize board - all dark}
  FOR x := 0 TO BOARD_WIDTH-1 DO
    FOR y := 0 TO BOARD_HEIGHT-1 DO
      board[x,y].tileType := ttDark;

  {Generate starting tiles for each prisoner}
  FOR pId := 1 TO MAX_PRISONERS DO
  BEGIN
    GenerateTile(board[prisoners[pId].x, prisoners[pId].y]);
  END;

  {Initial illumination calculation}
  CalculateIllumination;
  GenerateNewTiles;

  LogMessage('Welcome to CAGE OF SHADOWS!');
  LogMessage('Collect keys and reach the gate together.');
END;

{============================================================================}
{ INPUT HANDLING                                                            }
{============================================================================}

PROCEDURE HandleInput(VAR continueTurn: BOOLEAN);
VAR
  key: CHAR;
BEGIN
  repeat
    key := ReadKey;

    CASE key OF
      #72, 'W': {Up/North}
        BEGIN MovePrisoner(activePrisoner, dirNorth); continueTurn := TRUE; END;
      #80, 'S': {Down/South or Stay}
        IF (key = 'S') OR (key = 's') THEN
          StayPrisoner(activePrisoner)
        ELSE
          MovePrisoner(activePrisoner, dirSouth);
        continueTurn := TRUE;

      #75, 'A': {Left/West}
        BEGIN MovePrisoner(activePrisoner, dirWest); continueTurn := TRUE; END;
      #77, 'D': {Right/East}
        BEGIN MovePrisoner(activePrisoner, dirEast); continueTurn := TRUE; END;

      'N', 'n': {Spend nerve}
        SpendNerve(activePrisoner);

      'Q', 'q': {Quit}
        BEGIN LogMessage('Game ended.'); continueTurn := FALSE; EXIT; END;
    END;

  UNTIL (key <> #0) AND (key <> #27); {Ignore extended keys and ESC}
END;

{============================================================================}
{ TURN PROCESSING                                                           }
{============================================================================}

PROCEDURE ProcessTurn;
VAR
  continueTurn: BOOLEAN;
BEGIN
  turnNumber := turnNumber + 1;
  continueTurn := TRUE;

  WHILE continueTurn DO
  BEGIN
    {Handle player input}
    HandleInput(continueTurn);

    IF NOT continueTurn THEN EXIT;

    {Update illumination after movement}
    CalculateIllumination;

    {Generate new tiles for newly lit spaces}
    GenerateNewTiles;

    {Remove unlit tiles}
    RemoveUnlitTiles;

    {Check relighting}
    CheckRelighting;

    {Handle falling prisoners}
    HandleFallingPrisoners;

    {Final Flickers phase - remove extra tile each turn}
    IF finalFlickers THEN
    BEGIN
      drawStack := drawStack - 1;
      IF drawStack < 0 THEN drawStack := 0;
    END;

    {Check for Final Flickers entry}
    IF (drawStack <= 5) AND NOT finalFlickers THEN
    BEGIN
      finalFlickers := TRUE;
      LogMessage('*** FINAL FLICKERS BEGINS ***');
    END;

    {Advance to next prisoner}
    activePrisoner := activePrisoner MOD MAX_PRISONERS + 1;

    {Skip dead prisoners}
    WHILE (prisoners[activePrisoner].state = psDead) AND 
          (turnNumber < 100) DO
      activePrisoner := activePrisoner MOD MAX_PRISONERS + 1;

    continueTurn := FALSE;
  END;
END;

{============================================================================}
{ MAIN GAME LOOP                                                            }
{============================================================================}

PROCEDURE ShowWinScreen;
BEGIN
  ClrScr;
  TextBackground(Green);
  TextColor(Yellow);
  
  GotoXY(20, 10);
  Write('VICTORY!');
  GotoXY(15, 12);
  Write('All prisoners escaped together!');
  GotoXY(18, 14);
  Write('Turns: ', turnNumber);
  
  TextBackground(Black);
  TextColor(White);
END;

PROCEDURE ShowLossScreen(reason: STRING);
BEGIN
  ClrScr;
  TextBackground(Red);
  TextColor(Yellow);
  
  GotoXY(20, 10);
  Write('DEFEAT');
  GotoXY(15, 12);
  Write(reason);
  GotoXY(18, 14);
  Write('Turns: ', turnNumber);
  
  TextBackground(Black);
  TextColor(White);
END;

BEGIN {MAIN}
  {Initialize game}
  InitializeGame;

  {Main game loop}
  REPEAT
    ClearScreen;

    {Process current turn}
    ProcessTurn;

    {Check win/loss conditions}
    IF CheckWinCondition THEN
    BEGIN
      ShowWinScreen;
      BREAK;
    END;

    IF CheckLossCondition THEN
    BEGIN
      ShowLossCondition('All prisoners lost or no escape possible.');
      BREAK;
    END;

  UNTIL FALSE;

  {Wait for key press}
  ReadKey;
END.