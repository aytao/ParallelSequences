open Parallelseq
module S : Sequence.S

val time : ('a -> 'b) -> 'a -> 'b * float