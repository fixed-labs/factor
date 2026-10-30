! Copyright (C) 2026 Jake Zerrer.
! See https://factorcode.org/license.txt for BSD license.
USING: effect-rows io ;
IN: effect-rows.streams

! Annotating io at the stream protocol instead of at individual words.
! With transitive rows on, every word that reaches one of these generics
! (print, ., printf, write-lines, ...) gets io in its row with no further
! annotation. Its own io label so it can be loaded without effect-rows.io.

EFFECT: stream-io

EFFECTFUL: stream-read1 ( stream -- elt | stream-io )
EFFECTFUL: stream-read-unsafe ( n buf stream -- count | stream-io )
EFFECTFUL: stream-read-until ( seps stream -- seq sep/f | stream-io )
EFFECTFUL: stream-read-partial-unsafe ( n buf stream -- count | stream-io )
EFFECTFUL: stream-readln ( stream -- str/f | stream-io )
EFFECTFUL: stream-contents* ( stream -- seq | stream-io )
EFFECTFUL: stream-write1 ( elt stream -- | stream-io )
EFFECTFUL: stream-write ( data stream -- | stream-io )
EFFECTFUL: stream-flush ( stream -- | stream-io )
EFFECTFUL: stream-nl ( stream -- | stream-io )
EFFECTFUL: stream-tell ( stream -- n | stream-io )
EFFECTFUL: stream-seek ( n seek-type stream -- | stream-io )
EFFECTFUL: stream-length ( stream -- n/f | stream-io )
