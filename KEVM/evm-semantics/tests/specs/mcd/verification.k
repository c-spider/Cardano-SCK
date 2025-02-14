requires "../lemmas.k"
requires "bin_runtime.k"
requires "storage.k"
requires "../infinite-gas.k"
requires "word-pack.k"

module VERIFICATION
    imports DSS-BIN-RUNTIME
    imports DSS-STORAGE
    imports LEMMAS-MCD
endmodule

module LEMMAS-MCD
    imports LEMMAS-MCD-HASKELL
    imports LEMMAS-MCD-JAVA
endmodule

module LEMMAS-MCD-SYNTAX
    imports LEMMAS

    syntax Bool ::= #notPrecompileAddress ( Int ) [function]
 // --------------------------------------------------------
    rule #notPrecompileAddress ( X ) => 0 ==Int X orBool (10 <=Int X andBool #rangeAddress(X))

    syntax Int ::= #string2Word ( String ) [function]
 // -------------------------------------------------
    rule #string2Word(S) => #asWord(#padRightToWidth(32, #parseByteStackRaw(S)))

    syntax Int ::= "#Wad" | "#Ray" | "#Rad"
 // ---------------------------------------
    rule #Wad => 1000000000000000000                            [macro]
    rule #Ray => 1000000000000000000000000000                   [macro]
    rule #Rad => 1000000000000000000000000000000000000000000000 [macro]

    syntax ByteArray ::= #asByteStackInWidth    ( Int, Int )                 [function]
                       | #asByteStackInWidthaux ( Int, Int, Int, ByteArray ) [function]
 // -----------------------------------------------------------------------------------
    rule #asByteStackInWidth(X, N) => #asByteStackInWidthaux(X, N -Int 1, N, .ByteArray)

    rule #asByteStackInWidthaux(X, I, N, WS) => #asByteStackInWidthaux(X, I -Int 1, N, nthbyteof(X, I, N) : WS) when I >Int 0
    rule #asByteStackInWidthaux(X, 0, N, WS) => nthbyteof(X, 0, N) : WS

    syntax Int ::= nthbyteof ( Int , Int , Int ) [function, smtlib(smt_nthbyteof), proj]
 // ------------------------------------------------------------------------------------
    rule nthbyteof(V, I, N) => nthbyteof(V /Int 256, I, N -Int 1) when N  >Int (I +Int 1) [concrete]
    rule nthbyteof(V, I, N) =>           V modInt 256             when N ==Int (I +Int 1) [concrete]

    syntax Int ::= #rmul ( Int , Int ) [function, smtlib(smt_rmul)]
 // ---------------------------------------------------------------
    rule #rmul(X, Y) => (X *Int Y) /Int #Ray

endmodule

module LEMMAS-MCD-HASKELL [symbolic, kore]
    imports LEMMAS-MCD-COMMON

    // ### flapper-yank-pass-rough

    rule #range(M:Memory [ K <- V ], START, WIDTH) => #range(M [ K := (V : .ByteArray) ], START, WIDTH)
      requires START <=Int K andBool K +Int 1 ==Int START +Int WIDTH
       andBool 0 <Int WIDTH andBool 0 <=Int START
       [concrete(K, V), simplification]

    rule #range(M:Memory [ K <- V ] [ K' := VS':ByteArray ], START, WIDTH) => #range(M [ K := (V : VS') ], START, WIDTH)
      requires START <=Int K andBool K' +Int #sizeByteArray(VS') ==Int START +Int WIDTH
       andBool 0 <Int WIDTH andBool 0 <=Int START
       andBool K +Int 1 ==Int K'
      [concrete(K, K', V, VS'), simplification]

endmodule

module LEMMAS-MCD-JAVA [symbolic, kast]
    imports LEMMAS-MCD-COMMON

    // ### flapper-yank-pass-rough

    rule #range(M:Memory [ K <- V ], START, WIDTH) => #range(M [ K := (V : .ByteArray) ], START, WIDTH)
      requires #isConcrete(K) andBool #isConcrete(V)
       andBool START <=Int K andBool K +Int 1 ==Int START +Int WIDTH
       andBool 0 <Int WIDTH andBool 0 <=Int START
       [simplification]

    rule #range(M:Memory [ K <- V ] [ K' := VS':ByteArray ], START, WIDTH) => #range(M [ K := (V : VS') ], START, WIDTH)
      requires #isConcrete(K) andBool #isConcrete(K') andBool #isConcrete(V) andBool #isConcrete(VS')
       andBool START <=Int K andBool K' +Int #sizeByteArray(VS') ==Int START +Int WIDTH
       andBool 0 <Int WIDTH andBool 0 <=Int START
       andBool K +Int 1 ==Int K'
      [simplification]

endmodule

module LEMMAS-MCD-COMMON
    imports LEMMAS-MCD-SYNTAX
    imports INFINITE-GAS
    imports WORD-PACK

    // ### vat-move-diff

    rule (W0 : WS) [ 0     .. WIDTH ] => W0 : (WS [ 0 .. WIDTH -Int 1 ]) requires 0 <Int WIDTH [simplification]
    rule (_  : WS) [ START .. WIDTH ] => WS [ START -Int 1 .. WIDTH ]    requires 0 <Int START [simplification]

    // ### cat-exhaustiveness

    rule #sizeByteArray(_WS [ START .. WIDTH ]) => WIDTH requires 0 <=Int START andBool 0 <=Int WIDTH [simplification]

    rule WS [ START .. WIDTH ] [ 0 .. WIDTH' ]  => WS [ START .. WIDTH' ] requires WIDTH' <=Int WIDTH [simplification]

    // ### cat-file-addr-pass-rough

    rule maskWordPackAddrUInt48UInt48_1 &Int ADDR => 0 requires #rangeAddress(ADDR) [simplification]

    // ### PERFORMANCE: dai-adduu-fail-rough
    // 99s -> 48s

    rule #sizeWordStack(WS, N) => #sizeWordStack(WS, 0) +Int N requires N =/=Int 0 [simplification]

    // ### PERFORMANCE: vat-deny-diff-fail-rough
    // 27.21m -> 3.16m

    rule M:Memory [ K <- V ]             [ K' <- V' ] => M [ K' <- V' ] [ K <- V ]   requires K' <Int K                                            [simplification]
    rule M:Memory [ K := BUF:ByteArray ] [ K' <- V' ] => M [ K' <- V' ] [ K := BUF ] requires K' <Int K orBool K +Int #sizeByteArray(BUF) <=Int K' [simplification]

    // ### dstoken-transferfrom-fail-rough

    rule chop(N +Int M) <Int N => true requires #rangeUInt(256, N) andBool #rangeUInt(256, M) andBool notBool #rangeUInt(256, N +Int M) [simplification]

    // ### dsvalue-read-pass

    rule M [ K <- V ] => M requires #lookup(M, K) ==Int V [simplification]

    // ### flipper-bids-pass-rough

    // This lemma is considered "safe enough" because `hash2` is a hash function over a large range and is very unlikely to overflow.
    // Note that this case comes from a solidity struct being accessed (hence the integer offsets), so it's an assumption built into the Solidity compiler anyway.
    rule chop(hash2(I1, I2) +Int N) => hash2(I1, I2) +Int N requires 0 <=Int N andBool N <Int 6 [simplification]

    rule ( BA1:ByteArray ++ BA2:ByteArray ) ++ BA3:ByteArray => BA1 ++ ( BA2 ++ BA3 ) [simplification]

    // ### vat-addui-fail-rough

    // Proof:
    // case sgn(X) ==Int  1
    //      X s<Word 0
    //   => X <Word 0           // sgn(X) ==Int 1 andBool sgn(0) ==Int 1
    //   => bool2Word(false)    // #rangeUInt(256, X)
    // case sgn(X) ==Int -1
    //      X s<Word 0
    //   => bool2Word(true)     // sgn(X) ==Int -1 andBool sgn(0) ==Int 1
    //
    // Via Z3 4.8.7:
    // ; 2^256
    // (declare-const pow256 Int)
    // (assert (= pow256 115792089237316195423570985008687907853269984665640564039457584007913129639936))
    //
    // ; 2^255
    // (declare-const pow255 Int)
    // (assert (= pow255 57896044618658097711785492504343953926634992332820282019728792003956564819968))
    //
    // ; sgn
    // (declare-fun sgn (Int) Int)
    // (assert (forall ((x Int)) (=> (and (>= x 0)      (< x pow255)) (= (sgn x)  1))))
    // (assert (forall ((x Int)) (=> (and (>= x pow255) (< x pow256)) (= (sgn x) -1))))
    //
    // ; s<Word
    // (declare-fun slt (Int Int) Bool)
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x)  1) (= (sgn y)  1)) (= (slt x y) (< x y)))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x)  1) (= (sgn y) -1)) (= (slt x y) false))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x) -1) (= (sgn y)  1)) (= (slt x y) true))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x) -1) (= (sgn y) -1)) (= (slt x y) (> x y)))))
    //
    // ;;;; proof
    //
    // ; uint256
    // (declare-const x Int)
    // (assert (and (>= x 0) (< x pow256)))
    //
    // (assert (not
    //     (= (slt x 0) (= (sgn x) -1))
    // ))
    // (check-sat)
    rule X s<Word 0 => bool2Word(sgn(X) ==Int -1) requires #rangeUInt(256, X) [simplification]

    rule sgn(chop(X)) ==Int -1 => X <Int 0 requires #rangeSInt(256, X) [simplification]

    // ### vat-mului-pass

    rule chop(X *Int chop(Y)) => chop(X *Int Y) [simplification]

    // Proof #rangeUInt(256, X) andBool #rangeSInt(256, Y) andBool #rangeSInt(256, X *Int Y) andBool Y =/=Int 0
    //      chop(X *Int Y) /sWord chop(Y)
    //   => #sgnInterp(sgn(chop(X *Int Y)) *Int sgn(chop(Y)), abs(chop(X *Int Y)) /Word abs(chop(Y)))
    // Focus: sgn(chop(X *Int Y)) *Int sgn(chop(Y))
    //      case 0 <=Int Y
    //           sgn(chop(X *Int Y)) *Int sgn(chop(Y))
    //        => sgn(chop(X *Int Y)) *Int sgn(Y)                     // chop(Y) ==Int Y
    //        => sgn(X *Int Y) *Int sgn(Y)                           // 0 <=Int X andBool 0 <=Int Y
    //        => 1 *Int 1                                            // 0 <=Int X *Int Y andBool 0 <=Int Y
    //        => 1
    //      case Y <Int 0
    //           sgn(chop(X *Int Y)) *Int sgn(chop(Y))
    //        => sgn(X *Int Y +Int pow256) *Int sgn(Y +Int pow256)   // chop(Y) ==Int Y +Int pow256
    //        => -1 *Int -1                                          // X *Int Y <Int 0 andBool Y <Int 0
    //        => 1
    // Focus: abs(chop(X *Int Y)) /Word abs(chop(Y))
    //      case 0 <=Int Y
    //           abs(chop(X *Int Y)) /Word abs(chop(Y))
    //        => abs(chop(X *Int Y)) /Int  abs(chop(Y))
    //        => abs(X *Int Y) /Int abs(Y)                                                   // 0 <=Int X andBool 0 <=Int Y andBool #rangeSigne andBool chop(Y) ==Int Y
    //        => X *Int Y /Int Y                                                             // #rangeSInt(256, X *Int Y) andBool 0 <=Int X *Int Y andBool #rangeSInt(256, Y) andBool 0 <=Int Y
    //        => X
    //      case Y <Int 0
    //           abs(chop(X *Int Y)) /Int abs(chop(Y))
    //        => abs(X *Int Y +Int pow256) /Int abs(Y +Int pow256)                           // #rangeSInt(256, X *Int Y) andBool chop(Y) ==Int Y +Int pow256
    //        => (0 -Word (X *Int Y +Int pow256)) /Int (0 -Word (Y +Int pow256))             // #rangeSInt(256, X *Int Y) andBool X *Int Y <Int 0 andBool #rangeSInt(256, Y) andBool Y <Int 0
    //        => (pow256 -Int (X *Int Y +Int pow256)) /Int (pow256 -Int (Y +Int pow256))     // 0 <Int (X *Int Y +Int pow256) andBool 0 <Int (Y +Int pow256)
    //        => (X *Int Y) /Int Y
    //        => X
    //
    // Via Z3 4.7.1:
    // ; 2^4 and 2^3 instead of 2^256 and 2^255 for small model proof
    // (declare-const pow256 Int)
    // (assert (= pow256 16))
    // (declare-const pow255 Int)
    // (assert (= pow255 8))
    //
    // ; sgn
    // (declare-fun sgn (Int) Int)
    // (assert (forall ((x Int)) (=> (and (>= x 0)      (< x pow255)) (= (sgn x)  1))))
    // (assert (forall ((x Int)) (=> (and (>= x pow255) (< x pow256)) (= (sgn x) -1))))
    //
    // ; s<Word
    // (declare-fun slt (Int Int) Bool)
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x)  1) (= (sgn y)  1)) (= (slt x y) (< x y)))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x)  1) (= (sgn y) -1)) (= (slt x y) false))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x) -1) (= (sgn y)  1)) (= (slt x y) true))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x) -1) (= (sgn y) -1)) (= (slt x y) (> x y)))))
    //
    // ; chop
    // (define-fun chop ((x Int)) Int (mod x pow256))
    //
    // ; /Word
    // ;(define-fun zdiv ((x Int) (y Int)) Int (ite (= y 0) 0 (div x y)))
    // (define-fun zdiv ((x Int) (y Int)) Int (div x y)) ; y is non-zero in the query below
    //
    // ; /sWord
    // (declare-fun sdiv (Int Int) Int)
    // (assert (forall ((x Int) (y Int)) (=> (> (* (sgn x) (sgn y)) 0) (= (sdiv x y)    (zdiv (abs x) (abs y)) ))))
    // (assert (forall ((x Int) (y Int)) (=> (< (* (sgn x) (sgn y)) 0) (= (sdiv x y) (- (zdiv (abs x) (abs y)))))))
    //
    // ; uint256
    // (define-fun uint256 ((x Int)) Bool (and (>= x 0) (< x pow256)))
    //
    // ; sint256
    // (define-fun sint256 ((x Int)) Bool (and (>= x (- pow255)) (< x pow255)))
    //
    // ;;;; proof
    //
    // (declare-const x Int)
    // (declare-const y Int)
    //
    // (assert (uint256 x))
    // (assert (sint256 y))
    // (assert (sint256 (* x y)))
    // (assert (not (= y 0)))
    //
    // (assert (not
    //     (= (sdiv (chop (* x y)) (chop y)) x)
    // ))
    // (check-sat)
    rule chop(X *Int Y) /sWord chop(Y) => X requires #rangeUInt(256, X) andBool #rangeSInt(256, Y) andBool #rangeSInt(256, X *Int Y) andBool Y =/=Int 0 [simplification]

    // ### vat-slip-pass-rough

    rule chop(X +Int chop(Y)) => chop(X +Int Y) [simplification]

    // ### vow-flog-fail-rough

    rule X -Word Y <=Int X => #rangeUInt(256, X -Int Y) requires #rangeUInt(256, X) andBool #rangeUInt(256, Y) [simplification]
    rule 0 <=Int X +Int Y => true requires 0 <=Int X andBool 0 <=Int Y                                         [simplification]

    // ### flipper-addu48u48-fail-rough

    rule maxUInt48 &Int (X +Int Y) <Int X => true requires #rangeUInt(48, X) andBool #rangeUInt(48, Y) andBool notBool (X +Int Y <Int pow48) [simplification]

    // ### vat-subui-fail-rough

    // ;(set-option :smt.mbqi true)
    //
    // ; 2^256
    // (declare-const pow256 Int)
    // (assert (= pow256 115792089237316195423570985008687907853269984665640564039457584007913129639936))
    //
    // ; 2^255
    // (declare-const pow255 Int)
    // (assert (= pow255 57896044618658097711785492504343953926634992332820282019728792003956564819968))
    //
    // ; sgn
    // (declare-fun sgn (Int) Int)
    // (assert (forall ((x Int)) (=> (and (>= x 0)      (< x pow255)) (= (sgn x)  1))))
    // (assert (forall ((x Int)) (=> (and (>= x pow255) (< x pow256)) (= (sgn x) -1))))
    //
    // ; s<Word
    // (declare-fun slt (Int Int) Bool)
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x)  1) (= (sgn y)  1)) (= (slt x y) (< x y)))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x)  1) (= (sgn y) -1)) (= (slt x y) false))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x) -1) (= (sgn y)  1)) (= (slt x y) true))))
    // (assert (forall ((x Int) (y Int)) (=> (and (= (sgn x) -1) (= (sgn y) -1)) (= (slt x y) (> x y)))))
    //
    // ; chop
    // (define-fun chop ((x Int)) Int (mod x pow256))
    // ;(simplify (chop -1))
    //
    // ; /Word
    // (define-fun zdiv ((x Int) (y Int)) Int (ite (= y 0) 0 (div x y)))
    //
    // ; /sWord
    // (declare-fun sdiv (Int Int) Int)
    // (assert (forall ((x Int) (y Int)) (=> (> (* (sgn x) (sgn y)) 0) (= (sdiv x y)    (zdiv (abs x) (abs y)) ))))
    // (assert (forall ((x Int) (y Int)) (=> (< (* (sgn x) (sgn y)) 0) (= (sdiv x y) (- (zdiv (abs x) (abs y)))))))
    //
    // ; uint256
    // (define-fun uint256 ((x Int)) Bool (and (>= x 0) (< x pow256)))
    //
    // ; sint256
    // (define-fun sint256 ((x Int)) Bool (and (>= x (- pow255)) (< x pow255)))
    //
    // ;;;;
    //
    // (declare-const x Int)
    // (declare-const y Int)

    // Via Z3 4.7.1:
    // (push)
    // (assert (not (=> (uint256 x) (= (slt 0 x) (and (= (sgn x) 1) (not (= x 0))) ) ) ))
    // (check-sat)
    // (pop)
    rule 0 s<Word X => bool2Word(sgn(X) ==Int 1 andBool X =/=Int 0) requires #rangeUInt(256, X) [simplification]

    // Via Z3 4.7.1:
    // (push)
    // (assert (not (=> (sint256 y) (= (= (sgn (chop y)) 1) (<= 0 y) ) ) ))
    // (check-sat)
    // (pop)
    rule sgn(chop(Y)) ==K 1 => 0 <=Int Y requires #rangeSInt(256, Y) [simplification]

    // ### vat-subui-pass-rough

    // Via Z3 4.7.1:
    // (push)
    // (assert (not (=> true (= (chop (- x (chop y))) (chop (- x y)) ) ) ))
    // (check-sat)
    // (pop)
    rule X -Word chop(Y) => chop(X -Int Y) [simplification]

    // ### end-pack-pass-rough

    rule ADDR in (SetItem(I) REST) => ADDR in REST requires #notPrecompileAddress(ADDR) andBool notBool #notPrecompileAddress(I) [simplification]

    // ### vat-subui-pass

    rule chop(X) ==K 0 => X ==Int 0 requires #rangeSInt(256, X) [simplification]

    // ### flopper-kick-pass-rough

    rule 0 <=Int X |Int Y => true requires 0 <=Int X andBool 0 <=Int Y [simplification]
    rule 0 <=Int X &Int Y => true requires 0 <=Int X andBool 0 <=Int Y [simplification]

    rule X |Int Y <Int pow256 => true requires X <Int pow256 andBool Y <Int pow256 [simplification]
    rule X &Int Y <Int pow256 => true requires X <Int pow256 andBool Y <Int pow256 [simplification]

    rule (maxUInt160 &Int (X |Int Y)) => (maxUInt160 &Int X) |Int (maxUInt160 &Int Y) [simplification]

    // ### flopper-tick-pass-rough

    rule chop(X *Int Y) => X *Int Y requires 0 <=Int X andBool 0 <=Int Y andBool X *Int Y <Int pow256 [simplification]

    // This proof ends up with side-conditions which look like this:
    // Tic ==K 0 andBool 0 ==K maxUInt48 &Int (#lookup(STORAGE, ADDR) /Int pow160) andBool Tic ==K maxUInt48 &Int (#lookup(STORAGE, ADDR) /Int pow160)
    // So we need this rule to do the structural simplification because the Java backend will not use this string of equalities to do the simplification directly.
    rule #WordPackAddrUInt48UInt48(ADDR, maxUInt48 &Int (ADDR_UINT48_UINT48 /Int pow160), UINT48_2) => #WordPackAddrUInt48UInt48(ADDR, 0, UINT48_2) requires maxUInt48 &Int (ADDR_UINT48_UINT48 /Int pow160) ==Int 0 [simplification]

    // ### flapper-yank-pass-rough

    rule M:Memory [ K := BUF:ByteArray ] [ K' := BUF':ByteArray ] => M [ K := (BUF [ 0 .. K' -Int K ]) ] [ K' := BUF' ]
      requires K <Int K'
       andBool K' <Int K +Int #sizeByteArray(BUF)
       andBool K +Int #sizeByteArray(BUF) <Int K' +Int #sizeByteArray(BUF')
      [simplification]

    rule X <Int X -Int Y => false requires 0 <=Int Y [simplification]
    rule X +Int Y <Int X => false requires 0 <=Int Y [simplification]

    // ### vow-cage-surplus-pass-rough

    rule <acctID> ACCTID </acctID>  ==K <acctID> ACCTID' </acctID> => ACCTID  ==Int ACCTID' [simplification]
    rule <acctID> ACCTID </acctID> =/=K <acctID> ACCTID' </acctID> => ACCTID =/=Int ACCTID' [simplification]

    rule ((K |-> V) REST) [ K' <- undef ] => REST                             requires K  ==K K' [simplification]
    rule ((K |-> V) REST) [ K' <- undef ] => (K |-> V) (REST [ K' <- undef ]) requires K =/=K K' [simplification]

    rule M:Map [ K1 <- V1 ] [ K2 <- V2 ] [ K1 <- V1' ] => M [ K1 <- V1' ] [ K2 <- V2 ] requires K1 =/=Int K2 [simplification]

    // ### end-cage-ilk-pass-rough

    rule M:Memory [ K1 := BUF1 ] [ K2 := BUF2 ] => M [ K2 := BUF2 ]
      requires K2 <=Int K1
       andBool K1 +Int #sizeByteArray(BUF1) <=Int K2 +Int #sizeByteArray(BUF2)
      [simplification]

    rule M:Memory [ K1 := (BUF11 ++ BUF12) ] [ K2 := BUF2 ] => M [ K1 +Int #sizeByteArray(BUF11) := BUF12 ] [ K2 := BUF2 ]
      requires K2 <=Int K1
       andBool K1 +Int #sizeByteArray(BUF11) <=Int K2 +Int #sizeByteArray(BUF2)
      [simplification]

    // ### vat-frob-diff-zero-dart-pass-rough

    rule chop( X -Int chop(Y))         => chop( X -Int Y)         [simplification]
    rule chop((X -Int chop(Y)) *Int Z) => chop((X -Int Y) *Int Z) [simplification]

    // ### vat-fork-diff-pass-rough

    rule chop(X +Int pow256)  => chop(X)        [simplification]
    rule chop(chop(X) *Int Y) => chop(X *Int Y) [simplification]

    // ### vow-cage-deficit-pass-rough

    rule (I1 +Int I2) -Int I1 => I2 [simplification]

    // ### flapper-tend-guy-diff-pass-rough

    rule ((I1 -Int I2) -Int I3) +Int I2 => I1 -Int I3 [simplification]

    rule M:Map [ K1 <- V1 ] [ K2 <- V2 ] [ K3 <- V3 ] [ K1 <- V4 ] => M [ K1 <- V4 ] [ K2 <- V2 ] [ K3 <- V3 ] requires K1 =/=Int K2 andBool K1 =/=Int K3 [simplification]

    // ### vat-fold-pass-rough

    rule chop(X *Int (Y +Int pow256)) => chop(X *Int Y) [simplification]

endmodule
