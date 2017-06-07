{-|
    Module      :  AERN2.MP.Enclosure
    Description :  Enclosure operations
    Copyright   :  (c) Michal Konecny
    License     :  BSD3

    Maintainer  :  mikkonecny@gmail.com
    Stability   :  experimental
    Portability :  portable

    Enclosure classes and operations.
-}
module AERN2.MP.Enclosure
(
  IsBall(..)
  , IsInterval(..), intervalFunctionByEndpoints, intervalFunctionByEndpointsUpDown
  , CanTestContains(..), CanMapInside(..), specCanMapInside
  , CanIntersectAssymetric(..), CanIntersect
  , CanIntersectBy, CanIntersectSameType
  , CanIntersectCNBy, CanIntersectCNSameType
  , CanUnionAssymetric(..), CanUnion, CanUnionBy, CanUnionSameType
  )
where

import Numeric.MixedTypes
-- import qualified Prelude as P

import Test.Hspec
import Test.QuickCheck

import qualified Control.CollectErrors as CE
import Control.CollectErrors (CollectErrors, EnsureCE, CanEnsureCE, ensureCE)

import AERN2.MP.ErrorBound

{- ball-specific operations -}

class IsBall t where
  type CentreType t
  centre :: t -> CentreType t
  centreAsBallAndRadius :: t-> (t,ErrorBound)
  centreAsBall :: t -> t
  centreAsBall = fst . centreAsBallAndRadius
  radius :: t -> ErrorBound
  radius = snd . centreAsBallAndRadius
  updateRadius :: (ErrorBound -> ErrorBound) -> (t -> t)
  {-|  When the radius of the ball is implicitly contributed to by imprecision in the centre
     (eg if the centre is a polynomial with inexact coefficients), move all that imprecision
     to the explicit radius, making the centre exact.  This may lose some information,
     but as a ball is equivalent to the original.
     For MPBall this function is pointless because it is equivalent to the identity.  -}
  makeExactCentre :: (IsBall t) => t -> t
  makeExactCentre v =
    updateRadius (+r) c
    where
    (c, r) = centreAsBallAndRadius v

{- interval-specific operations -}

class IsInterval i e where
  fromEndpoints :: e -> e -> i
  endpoints :: i -> (e,e)

{-|
    Computes a *monotone* ball function @f@ on intervals using the interval endpoints.
-}
intervalFunctionByEndpoints ::
  (IsInterval t t, HasEqCertainly t t)
  =>
  (t -> t) {-^ @fThin@: a version of @f@ that works well on thin intervals -} ->
  (t -> t) {-^ @f@ on *large* intervals -}
intervalFunctionByEndpoints fThin x
  | l !==! u = fThin l
  | otherwise = fromEndpoints (fThin l) (fThin u)
  where
  (l,u) = endpoints x

{-|
    Computes a *monotone* ball function @f@ on intervals using the interval endpoints.
-}
intervalFunctionByEndpointsUpDown ::
  (IsInterval t e)
  =>
  (e -> e) {-^ @fDown@: a version of @f@ working on endpoints, rounded down -} ->
  (e -> e) {-^ @fUp@: a version of @f@ working on endpoints, rounded up -} ->
  (t -> t) {-^ @f@ on intervals rounding *outwards* -}
intervalFunctionByEndpointsUpDown fDown fUp x =
  fromEndpoints (fDown l) (fUp u)
  where
  (l,u) = endpoints x


{- containment -}

class CanTestContains dom e where
  {-| Test if @e@ is inside @dom@. -}
  contains :: dom {-^ @dom@ -} -> e  {-^ @e@ -} -> Bool

class CanMapInside dom e where
  {-| Return some value contained in @dom@.
      The returned value does not have to equal the given @e@
      even if @e@ is already inside @dom@.
      All elements of @dom@ should be covered with roughly the same probability
      when calling this function for evenly distributed @e@'s.

      This function is intended mainly for generating values inside @dom@
      for randomised tests.
  -}
  mapInside :: dom {-^ @dom@ -} -> e  {-^ @e@ -} -> e

specCanMapInside ::
  (CanMapInside d e, CanTestContains d e
  , Arbitrary d, Arbitrary e, Show d, Show e)
  =>
  T d -> T e -> Spec
specCanMapInside (T dName :: T d) (T eName :: T e) =
  it ("CanMapInside " ++ dName ++ " " ++ eName) $ do
    property $
      \ (d :: d) (e :: e) ->
        contains d $ mapInside d e

{- intersection -}

type CanIntersect e1 e2 = (CanIntersectAssymetric e1 e2, CanIntersectAssymetric e1 e2)

class CanIntersectAssymetric e1 e2 where
  type IntersectionType e1 e2
  type IntersectionType e1 e2 = EnsureCN e1
  intersect :: e1 -> e2 -> IntersectionType e1 e2

type CanIntersectBy e1 e2 = (CanIntersect e1 e2, IntersectionType e1 e2 ~ e1)
type CanIntersectCNBy e1 e2 = (CanIntersect e1 e2, IntersectionType e1 e2 ~ EnsureCN e1)

type CanIntersectSameType e1 = CanIntersectBy e1 e1
type CanIntersectCNSameType e1 = CanIntersectCNBy e1 e1

instance CanIntersectAssymetric Bool Bool where
  intersect b1 b2
    | b1 == b2 = noNumErrors b1
    | otherwise = noValueNumErrorCertain $ NumError "empty Boolean intersection"

instance
  (CanIntersectCNSameType a, CanEnsureCN a)
  =>
  CanIntersectAssymetric (Maybe a) (Maybe a)
  where
  type IntersectionType (Maybe a) (Maybe a) = CollectNumErrors (Maybe a)
  intersect ma mb =
    case (ma, mb) of
     (Just a, Just b) -> justCN (intersect a b)
     (Just a, Nothing) -> justCN (ensureCN a)
     (Nothing, Just b) -> justCN (ensureCN b)
     _ -> noNumErrors Nothing

justCN :: (CanEnsureCN a) => EnsureCN a -> CN (Maybe a)
justCN aCN =
  case deEnsureCN aCN of
    Just a -> noNumErrors (Just a)
    _ -> fmap (const Nothing) aCN


-- --- Version that removes inner CN:
-- instance
--   (CanIntersectCNSameType a, CanEnsureCN a)
--   =>
--   CanIntersectAssymetric (Maybe a) (Maybe a)
--   where
--   type IntersectionType (Maybe a) (Maybe a) = CollectNumErrors (Maybe (WithoutCN (IntersectionType a a)))
--   intersect (Just a) (Just b) = fmap Just (intersect a b)
--   intersect (Just a) Nothing = fmap Just (ensureCN a)
--   intersect Nothing (Just b) = fmap Just (ensureCN b)
--   intersect Nothing Nothing = noNumErrors Nothing
--
instance
  (CanIntersectAssymetric e1 e2, Monoid es, CanEnsureCE es (IntersectionType e1 e2))
  =>
  CanIntersectAssymetric (CollectErrors es e1) (CollectErrors es e2)
  where
  type IntersectionType (CollectErrors es e1) (CollectErrors es e2) =
    EnsureCE es (IntersectionType e1 e2)
  intersect aCE bCE =
    do
    a <- aCE
    b <- bCE
    ensureCE $ intersect a b

{- union -}

type CanUnion e1 e2 = (CanUnionAssymetric e1 e2, CanUnionAssymetric e1 e2)

class CanUnionAssymetric e1 e2 where
  type UnionionType e1 e2
  type UnionionType e1 e2 = e1
  union :: e1 -> e2 -> UnionionType e1 e2

type CanUnionBy e1 e2 = (CanUnion e1 e2, UnionionType e1 e2 ~ e1)

type CanUnionSameType e1 = CanUnionBy e1 e1

instance
  (CanUnionAssymetric e1 e2, Monoid es, CanEnsureCE es (UnionionType e1 e2))
  =>
  CanUnionAssymetric (CollectErrors es e1) (CollectErrors es e2)
  where
  type UnionionType (CollectErrors es e1) (CollectErrors es e2) =
    EnsureCE es (UnionionType e1 e2)
  union aCE bCE =
    do
    a <- aCE
    b <- bCE
    ensureCE $ union a b

instance (CanUnionSameType t) => HasIfThenElse (Maybe Bool) t where
  ifThenElse (Just b) e1 e2 = if b then e1 else e2
  ifThenElse Nothing e1 e2 = e1 `union` e2
