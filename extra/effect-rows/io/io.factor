! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: effect-rows io ;
IN: effect-rows.io

! An io effect, asserted on a few words of basis/io without editing them.

EFFECT: io

EFFECTFUL: write ( str -- | io )
EFFECTFUL: print ( str -- | io )
EFFECTFUL: nl ( -- | io )
EFFECTFUL: flush ( -- | io )
EFFECTFUL: readln ( -- str/f | io )
