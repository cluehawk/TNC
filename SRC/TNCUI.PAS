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
procedure PromptSelectBoardCell(const G: TGameState; const Eligible: TBoolGrid;
  const Prompt: string; var SelX, SelY: Byte);
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

procedure SetHighlight(BlinkOn: Boolean);
begin
  if BlinkOn then
    TextAttr := AttrBlinkInverse
  else
    TextAttr := AttrInverse;
end;

procedure SetNormalText;
begin
  TextAttr := AttrNormal;
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

function ActivePrisonerAtCell(const G: TGameState; X, Y: Byte): Boolean;
begin
  ActivePrisonerAtCell := G.Prisoners[G.ActiveIndex].Alive and
                          (not G.Prisoners[G.ActiveIndex].Falling) and
                          (G.Prisoners[G.ActiveIndex].X = X) and
                          (G.Prisoners[G.ActiveIndex].Y = Y);
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
  S: string[4];
begin
  S := '    ';
  if not CellVisible(G, X, Y) then
  begin
    TileLine := S;
    Exit;
  end;

  S[2] := TileGlyph(G.Board[X, Y].Kind, G.Board[X, Y].Rot);
  S[3] := OverlayGlyph(G, X, Y);
  TileLine := S;
end;

procedure DrawBoard(const G: TGameState);
var
  X, Y, Row: Byte;
  ChLeft, ChMid, ChRight: Char;
begin
  WriteAt(2, 1, '6x6 Board - Active ' + PrisonerName(G.ActiveIndex) + ' ');

  for Y := 0 to BoardH do
  begin
    if Y = 0 then
    begin
      ChLeft := BoxChar(218);
      ChMid := BoxChar(194);
      ChRight := BoxChar(191);
    end
    else if Y = BoardH then
    begin
      ChLeft := BoxChar(192);
      ChMid := BoxChar(193);
      ChRight := BoxChar(217);
    end
    else
    begin
      ChLeft := BoxChar(195);
      ChMid := BoxChar(197);
      ChRight := BoxChar(180);
    end;

    Row := 2 + Y * 2;
    GotoXY(1, Row);
    Write(ChLeft);
    for X := 0 to BoardW - 1 do
    begin
      Write(BoxChar(196), BoxChar(196), BoxChar(196), BoxChar(196));
      if X < BoardW - 1 then
        Write(ChMid)
      else
        Write(ChRight);
    end;

    if Y < BoardH then
    begin
      Row := BoardCellScreenY(Y);
      GotoXY(1, Row);
      for X := 0 to BoardW - 1 do
      begin
        Write(BoxChar(179));
        if ActivePrisonerAtCell(G, X, Y) then
        begin
          SetHighlight(False);
          Write(TileLine(G, X, Y, 0));
          SetNormalText;
        end
        else
          Write(TileLine(G, X, Y, 0));
      end;
      Write(BoxChar(179));
    end;
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

  WriteAt(35, Row, S + '                            ');
end;

procedure DrawSide(const G: TGameState);
var
  I, V: Byte;
  S: string;
begin
  DrawBox(33, 2, 80, 15);
  WriteAt(35, 2, ' Status ');
  WriteAt(35, 3, '>> ' + PrisonerName(G.ActiveIndex) + ' TURN <<                            ');
  WriteAt(35, 4, 'Turn ' + NumStr(G.TurnNumber) + '  Draw ' + NumStr(G.DrawsRemaining) + '                       ');
  WriteAt(35, 5, 'Phase: ' + PhaseName(G.Phase) + '                                  ');
  V := G.ViewIndex;
  WriteAt(35, 6, 'View : ' + PrisonerName(V) + '                                   ');

  if G.Prisoners[V].Falling then
    S := 'falling'
  else
    S := NumStr(G.Prisoners[V].X) + ',' + NumStr(G.Prisoners[V].Y);
  WriteAt(35, 7, 'Pos  : ' + S + '                                    ');

  if G.Prisoners[V].Lit then
    WriteAt(35, 8, 'Light: lit                                    ')
  else
    WriteAt(35, 8, 'Light: lights out                             ');

  if G.Prisoners[V].HasKey then
    S := 'yes'
  else
    S := 'no';
  WriteAt(35, 9, 'Key  : ' + S + '   Nerve: ' + NumStr(G.Prisoners[V].Nerve) + '                         ');

  WriteAt(35, 10, 'Party');
  for I := 0 to PrisonerCount - 1 do
    DrawPrisonerLine(G, 11 + I, I);
end;

procedure DrawLog(const G: TGameState);
var
  I: Byte;
  StartLine: Byte;
  MoveText: string;
  HelpText: string;
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

  WriteAt(3, 20, 'Legend: inverse turn 1-4 prisoners + gate stack  S start  K key');
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

  HelpText := '   N extra action  TAB view  Q quit';
  if not G.Prisoners[G.ActiveIndex].Falling then
  begin
    if CanPassKey(G, G.ActiveIndex) then
      HelpText := '   P pass key' + HelpText;
    if G.Prisoners[G.ActiveIndex].Lit then
      HelpText := '   S stay' + HelpText
    else if G.Prisoners[G.ActiveIndex].Nerve > 0 then
      HelpText := '   S stay(1N)' + HelpText
    else
      HelpText := HelpText;
  end;

  WriteAt(3, 23, MoveText + HelpText);
  if G.Prisoners[G.ActiveIndex].Falling then
    WriteAt(3, 24, 'Falling turn: choose one of the shown re-entry directions.                ')
  else if not G.Prisoners[G.ActiveIndex].Lit then
    WriteAt(3, 24, 'Lights out: must move. Only the destination is revealed this turn.        ')
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
  WriteAt(12, 12, 'Symbols: inverse active 1-4 prisoners  S start  K key  G gate');
  WriteAt(12, 13, '         W wax eater  * crumble  O pit  blank = darkness');
  WriteAt(12, 15, 'I up  J left  K down  L right  P pass key  S stay');
  WriteAt(12, 16, 'Lights out: must move, or spend 1 nerve to stay');
  WriteAt(12, 17, 'Q quits to DOS');
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
          'P': begin Cmd := 'P'; Exit; end;
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

procedure PromptSelectBoardCell(const G: TGameState; const Eligible: TBoolGrid;
  const Prompt: string; var SelX, SelY: Byte);
var
  X, Y: Byte;
  Found: Boolean;
  Ch: Char;
begin
  Found := False;
  for Y := 0 to BoardH - 1 do
    for X := 0 to BoardW - 1 do
      if Eligible[X, Y] then
      begin
        SelX := X;
        SelY := Y;
        Found := True;
        Break;
      end;

  if not Found then
    Exit;

  repeat
    DrawGame(G);
    SetHighlight(True);
    GotoXY(BoardCellScreenX(SelX), BoardCellScreenY(SelY));
    Write(TileLine(G, SelX, SelY, 0));
    SetNormalText;
    WriteAt(3, 23, '                                                                            ');
    WriteAt(3, 24, '                                                                            ');
    WriteAt(3, 23, Prompt);
    WriteAt(3, 24, 'TAB cycle target   ENTER place wax eater');
    Ch := ReadKey;
    if Ch = #9 then
    begin
      repeat
        Inc(SelX);
        if SelX >= BoardW then
        begin
          SelX := 0;
          Inc(SelY);
          if SelY >= BoardH then
            SelY := 0;
        end;
      until Eligible[SelX, SelY];
    end;
  until Ch = #13;
end;

procedure WaitForKey;
begin
  ReadKey;
end;

end.
