{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE StandaloneDeriving #-}
module AERN2.Linear.Matrix
-- ()
where

import MixedTypesNumPrelude
-- import Numeric.CollectErrors (NumErrors, CanTakeErrors(..))
-- import qualified Numeric.CollectErrors as CN

-- import qualified Prelude as P

-- import qualified Debug.Trace as Debug
-- import Text.Printf (printf)

import qualified Linear.V as LV
import Linear.V (V)
import qualified Linear as L
import qualified Data.Vector as Vector
import GHC.TypeLits (KnownNat, SomeNat (SomeNat), someNatVal, natVal)
import Data.Typeable (Typeable, Proxy (Proxy))
import AERN2.Real (CReal, creal, prec, (?), bits)
import Data.Foldable (Foldable(toList))
import qualified Data.Map as Map
import AERN2.MP (MPBall (ball_value), mpBallP)
import AERN2.MP.Float (MPFloat) 
import GHC.Real (Fractional)
import Unsafe.Coerce (unsafeCoerce)

----------------------
-- hiding type Nat type parameters 
----------------------

data VN e = forall n. KnownNat n => VN (V n e)
  
deriving instance (Show e) => (Show (VN e))

vNFromList :: (Typeable e, Show e) => [e] -> VN e
vNFromList (es :: [e]) = 
  case someNatVal (length es) of
    Nothing -> error "internal error in vNFromList"
    Just (SomeNat (_ :: Proxy n)) ->
      VN (vectorN es :: V n e)

vectorN :: (KnownNat n) => [e] -> V n e
vectorN es =
    case LV.fromVector $ Vector.fromList es of
      Just v -> v
      _ -> error "convertExactly to V: list of incorrect length"

data MatrixRC e = forall rn cn. (KnownNat rn, KnownNat cn) => MatrixRC (V rn (V cn e))

deriving instance (Show e) => (Show (MatrixRC e))

matrixRCFromList :: (Typeable e, Show e) => [[e]] -> MatrixRC e
matrixRCFromList [] = error "matrixRCFromList called with the empty list"
matrixRCFromList rows@((row1 :: [e]):_) =
  case (someNatVal (length rows), someNatVal (length row1)) of
    (Just (SomeNat (_ :: Proxy rn)), Just (SomeNat (_ :: Proxy cn))) ->
      MatrixRC (matrixRC rows :: V rn (V cn e))
    _ -> error "internal error in matrixRCFromList"
  where
  matrixRC :: (Typeable e, KnownNat cn, KnownNat rn) => 
              [[e]] -> V rn (V cn e)
  matrixRC rows2 =
    case LV.fromVector $ Vector.fromList (map vectorN rows2) of
      Just v -> v
      _ -> error "convertExactly to MatrixRC: incorrect number of rows"

luDetFinite :: (Fractional e) => MatrixRC e -> e
luDetFinite (MatrixRC (mx :: V rn_t (V cn_t e))) 
  | rn_v == cn_v = L.luDetFinite (unsafeCoerce mx :: V rn_t (V rn_t e))
  | otherwise = error "luDetFinite called for a non-square matrix"
  where
  rn_v = natVal (Proxy :: Proxy rn_t)
  cn_v = natVal (Proxy :: Proxy cn_t)


{-
  Determinant using the Laplace method.
  
  This works OK for sparse matrices and signular matrices.
-}

detLaplace :: 
  (HasIntegers e, CanMulBy e Integer, CanAddSameType e, CanMulSameType e, Show e) =>
  (e -> Bool) -> MatrixRC e -> e
detLaplace isZero (MatrixRC mx) = 
  fst $ doRows submatrixResults0 mask0 (toList mx)
  where
  mask0 = take (LV.dim mx) alternatingSigns
  alternatingSigns :: [Integer]
  alternatingSigns = 1 : aux
    where
    aux = (-1) : alternatingSigns
  submatrixResults0 = Map.empty
  -- aux submatrixResults mask n s [] = (fromInteger_ s, submatrixResults)
  doRows submatrixResults _mask [] = (fromInteger_ 1, submatrixResults)
  doRows submatrixResults mask (row:restRows) =
    foldl doItem (fromInteger_ 0, submatrixResults) $ zip3 (toList row) mask (submasks mask)
    where
    doItem (value_prev, submatrixResults_prev) (item, itemSign, submask)
      | itemSign == 0 || isZero item = 
          (value_prev, submatrixResults_prev)
      | otherwise = 
          (value_prev + item * itemSign * determinantValue, submatrixResults_next)
      where
      (determinantValue, submatrixResults_next) =
        -- Debug.trace (printf "mask: %s\n" (show mask)) $
        case Map.lookup submask submatrixResults_prev of
          Just v  -> 
            -- Debug.trace (printf "LOOKED UP: submask = %s,, value = %s\n" (show submask) (show v)) $
            (v, submatrixResults_prev) -- use the memoized determinant
          _ -> 
            -- Debug.trace (printf "ADDING: submask = %s, value = %s\n" (show submask) (show v_item)) $
            (v_item, Map.insert submask v_item submatrixResults_item)
            where
            (v_item, submatrixResults_item) = doRows submatrixResults_prev submask restRows
        
  submasks mask = aux mask
    where
    aux [] = []
    aux (b:bs) 
      | b == 0 = 
        (0:bs) : (map (b:) (aux bs))
      | otherwise = 
        (0:(map negate bs)) : (map (b:) (aux bs))

  {-
    recurse from top row downwards, 
    going over all columns whose elements are not certainly zero, 
    each sub-matrix identified by:
      a vector of signs (-1,0,1) showing inactive columns and, eventualy, the sign of the permutation
    memoizing results for all sub-matrices to be reused when the same sub-matrix is needed again
  -}

{- mini tests -}

n1 :: Integer
n1 = 100

rows1I :: [[Rational]]
rows1I = [[ item i j  | j <- [1..n1] ] | i <- [1..n1]]
  where
  item i j
    | i == j = rational 1
    | j > i + 1 = rational 0
    | otherwise = 1/(i+j)

--------------------

rows1D :: [[Double]]
rows1D = map (map double) rows1I

m1D :: MatrixRC Double
m1D = matrixRCFromList rows1D

m1D_detLU :: Double
m1D_detLU = luDetFinite m1D

m1D_detLaplace :: Double
m1D_detLaplace = detLaplace (== 0) m1D

--------------------

rows1MP :: [[MPFloat]]
rows1MP = map (map (ball_value . mpBallP (prec 1000))) rows1I

m1MP :: MatrixRC MPFloat
m1MP = matrixRCFromList rows1MP

m1MP_detLU :: MPFloat
m1MP_detLU = luDetFinite m1MP

-- m1MP_detLaplace :: MPFloat
-- m1MP_detLaplace = detLaplace (== 0) m1MP

--------------------

rows1R :: [[CReal]]
rows1R = map (map creal) rows1I

m1R :: MatrixRC CReal
m1R = matrixRCFromList rows1R

m1R_detLaplace :: CReal
m1R_detLaplace = detLaplace (\(e :: CReal) -> (e ? (prec 10))!==! 0) m1R

m1R_detLaplaceBits :: CN MPBall
m1R_detLaplaceBits = m1R_detLaplace ? (bits 1000)

--------------------

b1D :: VN Double
b1D = vNFromList $ replicate n1 (double 1)

-- m1b1_solLU = case luSolve m1D b1D

