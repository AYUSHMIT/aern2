{-|
    Module      :  AERN2.Poly.Cheb.Eval
    Description :  Evaluation and range
    Copyright   :  (c) Michal Konecny
    License     :  BSD3

    Maintainer  :  mikkonecny@gmail.com
    Stability   :  experimental
    Portability :  portable

    Evaluation and range
-}

module AERN2.Poly.Cheb.Eval
-- (
-- )
where

import Numeric.MixedTypes
-- import qualified Prelude as P
-- import Text.Printf

-- import Test.Hspec
-- import Test.QuickCheck

import AERN2.MP.ErrorBound
import AERN2.MP.Ball
import AERN2.MP.Dyadic

import AERN2.Real

import AERN2.Interval
import AERN2.RealFun.Operations
import AERN2.RealFun.UnaryFun

import AERN2.Poly.Basics
import AERN2.Poly.Cheb.Type

{- evaluation -}

instance CanApply PolyBall MPBall where
  type ApplyType PolyBall MPBall = MPBall
  apply (Ball x e) y = updateRadius (+e) (apply x y)

instance
  (CanAddSubMulBy MPBall c, Ring c) =>
  CanApply (ChPoly c) MPBall where
  type ApplyType (ChPoly c) MPBall = MPBall
  apply = evalDirect

instance
  (CanAddSubMulBy MPBall c, Ring c) =>
  CanApply (ChPoly c) Dyadic where
  type ApplyType (ChPoly c) Dyadic = MPBall
  apply p = apply p . mpBall

evalDirect ::
  (Ring t, CanAddSubMulDivBy t Dyadic, CanDivBy t Integer,
   CanAddSubMulBy t c, Ring c)
  =>
  (ChPoly c) -> t -> t
evalDirect (ChPoly dom (Poly terms)) (xInDom :: t) =
    (b0 - b2)/2
    where
    x = fromDomToUnitInterval dom xInDom
    n = terms_degree terms
    (b0:_:b2:_) = bs
    bs :: [t]
    bs = reverse $ aux n z z
    z = convertExactly 0
    aux k bKp2 bKp1
        | k == 0 = [bKp2, bKp1, bK]
        | otherwise = bKp2 : aux (k - 1) bKp1 bK
        where
        bK = (a k) + 2 * x * bKp1 - bKp2
    a k = terms_lookupCoeffDoubleConstTerm terms k

fromDomToUnitInterval ::
  (CanAddSubMulDivBy t Dyadic) =>
  DyadicInterval -> t -> t
fromDomToUnitInterval (Interval l r) xInDom =
  (xInDom - m)/(0.5*(r-l))
  where
  m = (r+l)*0.5

{- range -}

sampledRange ::
  (CanAddSubMulBy MPBall c, Ring c) =>
  DyadicInterval -> Integer -> ChPoly c -> Interval MPBall MPBall
sampledRange (Interval l r) depth p =
    Interval minValue maxValue
    where
    minValue = foldl1 min samples
    maxValue = foldl1 max samples
    samples = map eval samplePoints
    eval = apply p
    samplePoints :: [Dyadic]
    samplePoints = [(l*i + r*(size - i))*(1/size) | i <- [0..size]]
    size = 2^depth

instance CanApply (ChPoly MPBall) DyadicInterval where
  type ApplyType (ChPoly MPBall) DyadicInterval = (Interval CauchyReal CauchyReal, ErrorBound)
  apply = rangeViaUnaryFun
  -- apply = rangeViaRoots

rangeViaUnaryFun :: (ChPoly MPBall) -> DyadicInterval -> (Interval CauchyReal CauchyReal, ErrorBound)
rangeViaUnaryFun p di = (apply f di, e)
  where
  f :: UnaryFun
  (f, e) = convertExactly p

instance ConvertibleExactly (ChPoly MPBall) (UnaryFun, ErrorBound) where
  safeConvertExactly cp@(ChPoly dom _p) = Right (UnaryFun dom eval, e)
    where
    e = radius cp
    cpExact = centreAsBall cp
    eval = fmap $ evalDirect cpExact
