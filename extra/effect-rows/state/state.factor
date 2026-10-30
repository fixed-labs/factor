! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: effect-rows fry kernel namespaces ;
IN: effect-rows.state

! A state effect. The runtime is a dynamic variable standing in for a
! real perform/handle implementation; only the static row matters here.

EFFECT: state

SYMBOL: state-cell

E: get-state ( -- x | state ) state-cell get ;

E: put-state ( x -- | state ) state-cell set ;

! Runs quot with a fresh state initialised to init, then pushes the final
! state. Discharges state; every other effect of quot passes through ..e.
HANDLER: with-state ( ..a init quot: ( ..a -- ..b | state ..e ) -- ..b final | ..e )
    state-cell swap '[ @ state-cell get ] with-variable ;

! Like with-state, but the quotation may perform nothing except state.
HANDLER: with-pure-state ( init quot: ( -- | state ) -- final | )
    with-state ;
