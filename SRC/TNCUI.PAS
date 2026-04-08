unit TNCUI;

interface

uses
  Crt,
  TNCDef,
  TNCRule;

procedure TitleScreen;
procedure DrawGame(const G: TGameState);
procedure GetAction(var G: TGameState; var Cmd: Char; var Dir: TDirection);
function PromptYesNo(const Prompt: string): Boolean;
procedure WaitForKey;
procedure WriteAt(X, Y: Byte; S: string);

implementation

function BoxChar(Code: Byte): Char;
begin
  BoxChar := Chr(Code);
end;

function NumStr(N: Word): string;
var
  S: string;
begin
  Str(N, S);
  NumStr := S;
end;

procedure WriteAt(X, Y: Byte; S: string);
begin
  GotoXY(X, Y);
  Write(S);
end;

procedure DrawBox(X1, Y1, X2, Y2: Byte);
var
  X, Y: Byte;
begin
  GotoXY(X1, Y1);
  Write(BoxChar(218));
  for X := X1 + 1 to X2 - 1 do
    Write(BoxChar(196));
  Write(BoxChar(191));

  for Y := Y1 + 1 to Y2 - 1 do
  begin
    GotoXY(X1, Y);
    Write(BoxChar(179));
    GotoXY(X2, Y);
    Write(BoxChar(179));
  end;

  GotoXY(X1, Y2);
  Write(BoxChar(192));
  for X := X1 + 1 to X2 - 1 do
    Write(BoxChar(196));
  Write(BoxChar(217));
end;

function PassageGlyph(const Cell: TCell): Char;
var
  Mask: Byte;
begin
  if not IsPresent(Cell) then
  begin
    PassageGlyph := ' ';
    Exit;
  end;

  if Cell.Kind = tkPit then
  begin
    PassageGlyph := 'O';
    Exit;
  end;

  Mask := OpenMask(Cell.Kind, Cell.Rot);
  case Mask of
     0: PassageGlyph := ' ';
     3: PassageGlyph := BoxChar(192);
     5: PassageGlyph := BoxChar(179);
     6: PassageGlyph := BoxChar(218);
     7: PassageGlyph := BoxChar(195);
     9: PassageGlyph := BoxChar(217);
    10: PassageGlyph := BoxChar(196);
    11: PassageGlyph := BoxChar(193);
    12: PassageGlyph := BoxChar(191);
    13: PassageGlyph := BoxChar(180);
    14: PassageGlyph := BoxChar(194);
    15: PassageGlyph := BoxChar(197);
  else
    PassageGlyph := '?';
  end;
end;

function OverlayGlyph(const G: TGameState; X, Y: Byte): Char;
var
  I, Count, LastSeen: Byte;
begin
  Count := 0;
  LastSeen := 0;
  for I := 0 to PrisonerCount - 1 do
    if G.Prisoners[I].Alive and (not G.Prisoners[I].Falling) and
       (G.Prisoners[I].X = X) and (G.Prisoners[I].Y = Y) then
    begin
      Inc(Count);
      LastSeen := I;
    end;

  if Count > 1 then
  begin
    OverlayGlyph := '+';
    Exit;
  end;
  if Count = 1 then
  begin
    if LastSeen = G.ActiveIndex then
      OverlayGlyph := '@'
    else
      OverlayGlyph := Char(Ord('1') + LastSeen);
    Exit;
  end;

  if not IsPresent(G.Board[X, Y]) then
  begin
    OverlayGlyph := ' ';
    Exit;
  end;

  case G.Board[X, Y].Feature of
    ftKey: OverlayGlyph := 'K';
    ftGate: OverlayGlyph := 'G';
    ftCrumbleFresh, ftCrumbleArmed: OverlayGlyph := '*';
    ftMonster: OverlayGlyph := 'W';
  else
    if G.Board[X, Y].Kind = tkStart then
      OverlayGlyph := 'S'
    else
      OverlayGlyph := ' ';
  end;
end;

function CellVisible(const G: TGameState; X, Y: Byte): Boolean;
begin
  CellVisible := IsPresent(G.Board[X, Y]) and
                 ((cfLit in G.Board[X, Y].Flags) or
                  (cfOccupied in G.Board[X, Y].Flags) or
                  (cfPermanent in G.Board[X, Y].Flags));
end;

function TileLine(const G: TGameState; X, Y, Line: Byte): string;
var
  S: string[6];
begin
  S := '      ';
  if not CellVisible(G, X, Y) then
  begin
    TileLine := S;
    Exit;
  end;

  if Line = 0 then
  begin
    S[3] := PassageGlyph(G.Board[X, Y]);
    S[4] := OverlayGlyph(G, X, Y);
  end
  else
  begin
    if CellOpen(G.Board[X, Y], dirNorth) then
      S[3] := '|';
    if CellOpen(G.Board[X, Y], dirSouth) then
      S[4] := '|';
    if CellOpen(G.Board[X, Y], dirWest) then
      S[2] := '-';
    if CellOpen(G.Board[X, Y], dirEast) then
      S[5] := '-';
  end;

  if G.Board[X, Y].Kind = tkPit then
  begin
    S := '  O   ';
    if Line = 1 then
      S := '      ';
  end;
  TileLine := S;
end;

procedure DrawBoard(const G: TGameState);
var
  X, Y: Byte;
begin
  DrawBox(1, 2, 40, 15);
  WriteAt(3, 2, ' 6x6 Board - Active ' + PrisonerName(G.ActiveIndex) + ' ');
  for Y := 0 to BoardH - 1 do
    for X := 0 to BoardW - 1 do
    begin
      GotoXY(3 + X * 6, 3 + Y * 2);
      Write(TileLine(G, X, Y, 0));
      GotoXY(3 + X * 6, 4 + Y * 2);
      Write(TileLine(G, X, Y, 1));
    end;
end;

procedure DrawPrisonerLine(const G: TGameState; Row, Index: Byte);
var
  S: string;
begin
  if Index = G.ActiveIndex then
    S := '>'
  else
    S := ' ';
  S := S + PrisonerName(Index) + ' ';
  if G.Prisoners[Index].Lit then
    S := S + 'LIT '
  else
    S := S + 'OUT ';

  if G.Prisoners[Index].HasKey then
    S := S + 'KEY '
  else
    S := S + '--  ';

  S := S + 'N' + NumStr(G.Prisoners[Index].Nerve);

  if G.Prisoners[Index].Falling then
    S := S + ' FALL'
  else
    S := S + '     ';

  WriteAt(43, Row, S + '                    ');
end;

procedure DrawSide(const G: TGameState);
var
  I, V: Byte;
  S: string;
begin
  DrawBox(41, 2, 80, 15);
  WriteAt(43, 2, ' Status ');
  WriteAt(43, 3, '>> ' + PrisonerName(G.ActiveIndex) + ' TURN <<                    ');
  WriteAt(43, 4, 'Turn ' + NumStr(G.TurnNumber) + '  Draw ' + NumStr(G.DrawsRemaining) + '               ');
  WriteAt(43, 5, 'Phase: ' + PhaseName(G.Phase) + '                          ');
  V := G.ViewIndex;
  WriteAt(43, 6, 'View : ' + PrisonerName(V) + '                           ');

  if G.Prisoners[V].Falling then
    S := 'falling'
  else
    S := NumStr(G.Prisoners[V].X) + ',' + NumStr(G.Prisoners[V].Y);
  WriteAt(43, 7, 'Pos  : ' + S + '                            ');

  if G.Prisoners[V].Lit then
    WriteAt(43, 8, 'Light: lit                            ')
  else
    WriteAt(43, 8, 'Light: lights out                     ');

  if G.Prisoners[V].HasKey then
    S := 'yes'
  else
    S := 'no';
  WriteAt(43, 9, 'Key  : ' + S + '   Nerve: ' + NumStr(G.Prisoners[V].Nerve) + '                 ');

  WriteAt(43, 10, 'Party');
  for I := 0 to PrisonerCount - 1 do
    DrawPrisonerLine(G, 11 + I, I);
end;

procedure DrawLog(const G: TGameState);
var
  I: Byte;
  StartLine: Byte;
  MoveText: string;
begin
  DrawBox(1, 16, 80, 25);
  WriteAt(3, 16, ' Log ');
  for I := 0 to 7 do
    WriteAt(3, 17 + I, '                                                                          ');

  if G.LogCount > 3 then
    StartLine := G.LogCount - 3
  else
    StartLine := 0;

  if G.LogCount > 0 then
    for I := StartLine to G.LogCount - 1 do
      WriteAt(3, 17 + (I - StartLine), LogMessage(G, I));

  WriteAt(3, 20, 'Legend: @ active 1-4 others + stack  S start  K key  G gate');
  WriteAt(3, 21, '        W wax eater  * crumble  O pit  blank = darkness');
  WriteAt(3, 22, 'Turn now: >> ' + PrisonerName(G.ActiveIndex) + ' <<');

  if G.Prisoners[G.ActiveIndex].Falling then
  begin
    MoveText := 'Re-enter:';
    if CanReEnterDirection(G, G.ActiveIndex, dirNorth) then
      MoveText := MoveText + ' I';
    if CanReEnterDirection(G, G.ActiveIndex, dirWest) then
      MoveText := MoveText + ' J';
    if CanReEnterDirection(G, G.ActiveIndex, dirSouth) then
      MoveText := MoveText + ' K';
    if CanReEnterDirection(G, G.ActiveIndex, dirEast) then
      MoveText := MoveText + ' L';
    if Length(MoveText) = 9 then
      MoveText := 'Re-enter: none';
  end
  else
  begin
    MoveText := 'Moves:';
    if CanMoveDirection(G, G.ActiveIndex, dirNorth) then
      MoveText := MoveText + ' I';
    if CanMoveDirection(G, G.ActiveIndex, dirWest) then
      MoveText := MoveText + ' J';
    if CanMoveDirection(G, G.ActiveIndex, dirSouth) then
      MoveText := MoveText + ' K';
    if CanMoveDirection(G, G.ActiveIndex, dirEast) then
      MoveText := MoveText + ' L';
    if Length(MoveText) = 6 then
      MoveText := 'Moves: none';
  end;

  WriteAt(3, 23, MoveText + '   S stay  N extra action  TAB view  Q quit');
  if G.Prisoners[G.ActiveIndex].Falling then
    WriteAt(3, 24, 'Falling turn: choose one of the shown re-entry directions.                ')
  else
    WriteAt(3, 24, 'Movement keys: I up, J left, K down, L right.                             ');
end;

procedure DrawGame(const G: TGameState);
begin
  TextBackground(Black);
  TextColor(LightGray);
  ClrScr;
  DrawBoard(G);
  DrawSide(G);
  DrawLog(G);
end;

procedure TitleScreen;
begin
  TextBackground(Black);
  TextColor(LightGray);
  ClrScr;
  DrawBox(8, 4, 73, 21);
  WriteAt(21, 6, 'THE NIGHT CAGE - DOS TEXT PROTOTYPE');
  WriteAt(12, 8, 'Four prisoners wake in separate pools of candlelight.');
  WriteAt(12, 9, 'Keep the maze lit, gather 4 keys, then meet on one gate.');
  WriteAt(12, 10, 'Wax eaters hunt straight passages. Darkness devours the rest.');
  WriteAt(12, 12, 'Symbols: @ active 1-4 prisoners  S start  K key  G gate');
  WriteAt(12, 13, '         W wax eater  * crumble  O pit  blank = darkness');
  WriteAt(12, 15, 'I up  J left  K down  L right  S stay  N extra action');
  WriteAt(12, 16, 'Q quits to DOS');
  WriteAt(12, 19, 'Press any key to begin.');
  ReadKey;
end;

procedure GetAction(var G: TGameState; var Cmd: Char; var Dir: TDirection);
var
  Ch: Char;
begin
  repeat
    Ch := ReadKey;
    if Ch = #9 then
    begin
      G.ViewIndex := (G.ViewIndex + 1) mod PrisonerCount;
      AddLog(G, 'Viewing ' + PrisonerName(G.ViewIndex) + ' in the side panel.');
      DrawGame(G);
    end;
    if Ch <> #9 then
    begin
      if Ch = #0 then
      begin
        Ch := ReadKey;
        case Ord(Ch) of
          72: begin Cmd := 'M'; Dir := dirNorth; Exit; end;
          77: begin Cmd := 'M'; Dir := dirEast; Exit; end;
          80: begin Cmd := 'M'; Dir := dirSouth; Exit; end;
          75: begin Cmd := 'M'; Dir := dirWest; Exit; end;
        end;
      end
      else
      begin
        Ch := UpCase(Ch);
        case Ch of
          'Q': begin Cmd := 'Q'; Exit; end;
          'S': begin Cmd := 'S'; Exit; end;
          'N': begin Cmd := 'N'; Exit; end;
          'I': begin Cmd := 'M'; Dir := dirNorth; Exit; end;
          'L': begin Cmd := 'M'; Dir := dirEast; Exit; end;
          'K': begin Cmd := 'M'; Dir := dirSouth; Exit; end;
          'J': begin Cmd := 'M'; Dir := dirWest; Exit; end;
        end;
      end;
    end;
  until False;
end;

function PromptYesNo(const Prompt: string): Boolean;
var
  Ch: Char;
begin
  WriteAt(3, 24, '                                                                            ');
  WriteAt(3, 24, Prompt + ' (Y/N)');
  repeat
    Ch := UpCase(ReadKey);
  until Ch in ['Y', 'N'];
  PromptYesNo := Ch = 'Y';
end;

procedure WaitForKey;
begin
  ReadKey;
end;

end.
