#import "Math";

BLACK     :: Vector4.{0, 0, 0, 1};
BLACKISH  :: Vector4.{0.01, 0.01, 0.01, 1};
WHITE     :: Vector4.{1, 1, 1, 1};
DARK      :: Vector4.{cast(float)28/255, cast(float)28/255, cast(float)28/255, 1};
DARKER    :: Vector4.{cast(float)28/1.5/255, cast(float)28/1.5/255, cast(float)28/1.5/255, 1};
DARKLESS  :: Vector4.{cast(float)28*1.5/255, cast(float)28*1.5/255, cast(float)28*1.5/255, 1};
TEXT      :: Vector4.{cast(float)173/255, cast(float)174/255, cast(float)178/255, 1};
MUTED     :: Vector4.{cast(float)173/1.5/255, cast(float)174/1.5/255, cast(float)178/1.5/255, 1};
RED       :: Vector4.{cast(float)255/255, cast(float)67/255, cast(float)119/255, 1};

to_3f :: ($c: Vector4) -> [3]float {
  f: [3]float = ---;
  f[0] = c.x;
  f[1] = c.y;
  f[2] = c.z;
  return f;
}
