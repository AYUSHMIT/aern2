{-# LANGUAGE CPP #-}
{-|
    Module      :  AERN2.MP.Float.Constants
    Description :  Special constants NaN, infinity etc
    Copyright   :  (c) Michal Konecny
    License     :  BSD3

    Maintainer  :  mikkonecny@gmail.com
    Stability   :  experimental
    Portability :  portable

    Special constants NaN, infinity etc
-}

module AERN2.MP.Float.Constants
  (
    zero, one
#ifdef MPFRBackend
    , nan, infinity
#endif
  )
where

import Numeric.MixedTypes
import qualified Prelude as P
-- import Data.Ratio

import AERN2.MP.Float.Type
import AERN2.MP.Float.Conversions
import AERN2.MP.Float.Operators

zero, one :: MPFloat
zero = mpFloat 0
one = mpFloat 1

#ifdef MPFRBackend
nan, infinity :: MPFloat
nan = zero /. zero
infinity = one /. zero
#endif

itisNaN :: MPFloat -> Bool
itisNaN x = x *^ one /= x

itisInfinite :: MPFloat -> Bool
itisInfinite x =
  x *^ (mpFloat 2) P.== x
  &&
  x P./= (mpFloat 0)

instance CanTestFinite MPFloat where
  isInfinite = itisInfinite
  isFinite x = not (itisInfinite x || itisNaN x)

instance CanTestNaN MPFloat where
  isNaN = itisNaN
