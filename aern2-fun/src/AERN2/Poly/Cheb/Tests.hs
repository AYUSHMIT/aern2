{-# LANGUAGE CPP #-}
#define DEBUG
{-|
    Module      :  AERN2.Poly.Cheb.Tests
    Description :  Tests for Chebyshev-basis polynomials
    Copyright   :  (c) Michal Konecny
    License     :  BSD3

    Maintainer  :  mikkonecny@gmail.com
    Stability   :  experimental
    Portability :  portable

    Tests for Chebyshev-basis polynomials

    To run the tests using stack, execute:

    @
    stack test aern2-fun --test-arguments "-a 100 -m ChPoly"
    @
-}

module AERN2.Poly.Cheb.Tests
  (
    specChPoly, tChPolyMPBall
  , chPolyFromOps, ChPolyConstruction(..)
  )
where

#ifdef DEBUG
import Debug.Trace (trace)
#define maybeTrace trace
#else
#define maybeTrace (\ (_ :: String) t -> t)
#endif

import Numeric.MixedTypes
-- import qualified Prelude as P
-- import Data.Ratio
import Text.Printf

-- import qualified Data.Set as Set

import Test.Hspec
import Test.QuickCheck
-- import qualified Test.Hspec.SmallCheck as SC

-- import Numeric.CatchingExceptions

import AERN2.MP
import AERN2.MP.Dyadic
import AERN2.MP.Ball.Tests

import AERN2.Interval

import AERN2.RealFun.Operations

import AERN2.RealFun.SineCosine (sineWithAccuracyGuide)

import AERN2.Poly.Basics

import AERN2.Poly.Cheb.Type
import AERN2.Poly.Cheb.Eval ()
import AERN2.Poly.Cheb.Ring ()
import AERN2.Poly.Cheb.Field (chebDivideDCT)
import AERN2.Poly.Cheb.Maximum (minimumOptimisedWithAccuracy, maximumOptimisedWithAccuracy)
-- import AERN2.Poly.Cheb.Integration ()

data ChPolyConstruction =
  ChPolyConstruction
  { cpConstr_acGuide :: Accuracy
  , cpConstr_dom :: DyadicInterval
  , cpConstr_i0 :: FnIndex
  , cpConstr_opIndices :: [(OpIndex, [FnIndex])]
  }
  deriving (Show)


chPolyFromOps :: ChPolyConstruction -> ChPoly MPBall
chPolyFromOps (ChPolyConstruction acGuide dom i0 opIndices) =
  applyOps opIndices (fns !! i0)
  where
  fns = map snd $ basicFunctions dom
  applyOps [] fn = centreAsBall fn
  applyOps ((opIndex, operandIndices):rest) fn =
    applyOps rest newFn
    where
    (_arity, opList) = operations !! opIndex
    operands = map (fns !!) operandIndices
    newFn = centreAsBall $ reduceSizeUsingAccuracyGuide acGuide $ opList (fn : operands)

type OpIndex = Integer
type Arity = Integer

operations :: [(Arity, [ChPoly MPBall] -> ChPoly MPBall)]
operations =
  [op2 (+), op2 (-), op2 (*), op2 (*)]
    -- , op1 (sineWithAccuracyGuide acGuide), op1 (cosineWithAccuracyGuide acGuide)]
    -- , op1 recipShift]
  where
  -- op1 op = (1, \[e] -> op e)
  op2 op = (2, \[e1,e2] -> op e1 e2)
  -- recipShift p = chebDivideDCT acGuide (c 1) (p + lb + 1)
  --   where
  --   lb :: MPBall
  --   (lb, _) =
  --       endpoints $
  --         -- minimumOverDom p (getDomain p)
  --         minimumOptimisedWithAccuracy acGuide p (mpBall l) (mpBall r) 5 5
  --         where
  --         (Interval l r) = getDomain p

type FnIndex = Integer
type Frequency = Integer

basicFunctions :: DyadicInterval -> [(Frequency, ChPoly MPBall)]
basicFunctions dom = [(10,x), (1, c 0.5), (1, c 2), (1, c 100), (1, c (0.5^20))]
  where
  x = varFn (constFn (dom, 0)) ()
  c :: (CanBeDyadic t, ConvertibleExactly Dyadic c) => t -> ChPoly c
  c n = constFn (dom, dyadic n)

instance HasDomain ChPolyConstruction where
  type Domain ChPolyConstruction = DyadicInterval
  getDomain = cpConstr_dom

instance
  -- (Arbitrary c, IsBall c, Show c) => Arbitrary (ChPolyConstruction c)
  Arbitrary ChPolyConstruction
  where
  arbitrary =
    arbitraryWithDom =<< arbitraryNonEmptySmallInterval

instance
  -- (Arbitrary c, IsBall c, Show c) => ArbitraryWithDom (ChPolyConstruction c)
  ArbitraryWithDom (ChPolyConstruction)
  where
  arbitraryWithDom dom =
    sized withSize
    where
    withSize size =
      do
      numOfOps <- growingElements [0..(10+size)]
      ops <- vectorOf (int numOfOps) (growingElements opIndicesArities)
      fn0 <- elementsWeighted fnIndices
      opIndices <- mapM addOperands ops
      return $ ChPolyConstruction acGuide dom fn0 opIndices
      where
      opIndicesArities = zip [0..] $ map fst operations
      fnIndices = map (\(i,(n,_)) -> (n,i)) $ zip [0..] $ basicFunctions dom
      elementsWeighted es = frequency $ map (\(n,e) -> (int n, return e)) es
      acGuide = bits $ 10 + size
      addOperands (i, arity) =
        do
        operandIndices <- mapM getOperandIndex [2..arity]
        return (i, operandIndices)
        where
        getOperandIndex _ = elementsWeighted fnIndices

instance
  Arbitrary (FnAndDescr (ChPoly MPBall))
  where
  arbitrary =
    do
    constr <- arbitrary
    return $ FnAndDescr (chPolyFromOps constr) (show constr)

instance
  ArbitraryWithDom (FnAndDescr (ChPoly MPBall))
  where
  arbitraryWithDom dom =
    do
    constr <- arbitraryWithDom dom
    return $ FnAndDescr (chPolyFromOps constr) (show constr)

instance Arbitrary (ChPoly MPBall) where
  arbitrary =
    do
    (FnAndDescr f _) <- arbitrary
    return f

{-|
  A runtime representative of type @ChPoly MPBall@.
  Used for specialising polymorphic tests to concrete types.
-}
tChPolyMPBall :: T (ChPoly MPBall)
tChPolyMPBall = T "ChPolyMPBall"

anyFn :: FnAndDescr (ChPoly MPBall) -> FnAndDescr (ChPoly MPBall)
anyFn = id

makeFnPositive :: FnAndDescr (ChPoly MPBall) -> FnAndDescr (ChPoly MPBall)
makeFnPositive (FnAndDescr p pDescr) =
  FnAndDescr res $ "makeFnPositive (" ++ pDescr ++ ")"
  where
  res
    | lb !>! 0 = p
    | otherwise = centreAsBall $ p - lb + 1
  Interval l r = getDomain p
  lb :: MPBall
  (lb, _) = endpoints $ minimumOptimisedWithAccuracy (bits 0) p (mpBall l) (mpBall r) 5 5

makeFnSmallRange :: Integer -> FnAndDescr (ChPoly MPBall) -> FnAndDescr (ChPoly MPBall)
makeFnSmallRange limit (FnAndDescr p pDescr) =
  maybeTrace (printf "makeFnSmallRange: p = %s" (show p)) $
  maybeTrace (printf "makeFnSmallRange: p construction = %s" pDescr) $
  maybeTrace (printf "makeFnSmallRange: radius p = %s" (show (radius p))) $
  maybeTrace (printf "makeFnSmallRange: lb = %s" (show lb)) $
  maybeTrace (printf "makeFnSmallRange: ub = %s" (show ub)) $
  FnAndDescr res $ "makeFnSmallRange " ++ show limit ++  " (" ++ pDescr ++ ")"
  where
  res
    | b !<! limit = p
    | otherwise = centreAsBall $ (limit * p / b)
  b = ub `max` (-lb)
  lb, ub :: MPBall
  -- (lb, _) = endpoints $ minimumOverDom p (getDomain p)
  -- (_, ub) = endpoints $ maximumOverDom p (getDomain p)
  (lb, _) = endpoints $ minimumOptimisedWithAccuracy (bits 0) p (mpBall l) (mpBall r) 5 5
  (_, ub) = endpoints $ maximumOptimisedWithAccuracy (bits 0) p (mpBall l) (mpBall r) 5 5
  Interval l r = getDomain p


-- precondAnyT :: t -> Bool
-- precondAnyT _t = True
--
-- precondNonZeroT :: (HasEqCertainly t Integer) => t -> Bool
-- precondNonZeroT t = t !/=! 0
--
-- precondSmallT :: (HasOrderCertainly t Integer) => t -> Bool
-- precondSmallT t = -1000 !<=! t && t !<=! 1000

specChPoly :: Spec
specChPoly =
  describe ("ChPoly") $ do
    describe "evaluation" $ do
      specEvalConstFn tMPBall tChPolyMPBall tMPBall
      specEvalUnaryVarFn tChPolyMPBall tMPBall
    describe "ring" $ do
      specFnPointwiseOp2 tChPolyMPBall tMPBall "+" (+) (+) anyFn anyFn
      specFnPointwiseOp2 tChPolyMPBall tMPBall "-" (-) (-) anyFn anyFn
      specFnPointwiseOp2 tChPolyMPBall tMPBall "*" (*) (*) anyFn anyFn
    describe "size reduction" $ do
      specFnPointwiseOp1 tChPolyMPBall tMPBall "reduce size (bits=10)" (reduceSizeUsingAccuracyGuide (bits 10)) id anyFn
      specFnPointwiseOp1 tChPolyMPBall tMPBall "reduce size (bits=0)" (reduceSizeUsingAccuracyGuide (bits 0)) id anyFn
      -- specCanReduceSizeUsingAccuracyGuide tChPolyMPBall
    describe "range" $ do
      specCanMaximiseOverDom tChPolyMPBall tMPBall
    describe "trigonometric" $ do
      specFnPointwiseOp1 tChPolyMPBall tMPBall "sine" (sineWithAccuracyGuide (bits 10)) (sin) (makeFnSmallRange 10)
    describe "field" $ do
      specFnPointwiseOp2 tChPolyMPBall tMPBall "/" (chebDivideDCT (bits 0)) (/) anyFn makeFnPositive
