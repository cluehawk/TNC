unit TNCRand;

interface

uses
  Dos,
  TNCDef;

procedure InitSeedFromClock(var Seed: Word);
function NextRandom(var Seed: Word): Word;
function RandomRange(var Seed: Word; MaxValue: Word): Word;

implementation

procedure InitSeedFromClock(var Seed: Word);
var
  H, M, S, HS: Word;
begin
  GetTime(H, M, S, HS);
  Seed := (H shl 11) xor (M shl 5) xor (S shl 1) xor HS xor $A55A;
  if Seed = 0 then
    Seed := $1357;
end;

function NextRandom(var Seed: Word): Word;
begin
  Seed := Seed * 25173 + 13849;
  NextRandom := Seed;
end;

function RandomRange(var Seed: Word; MaxValue: Word): Word;
begin
  if MaxValue = 0 then
    RandomRange := 0
  else
    RandomRange := NextRandom(Seed) mod MaxValue;
end;

end.
