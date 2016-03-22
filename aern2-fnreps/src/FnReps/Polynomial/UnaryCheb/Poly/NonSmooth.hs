module FnReps.Polynomial.UnaryCheb.Poly.NonSmooth where

import AERN2.RealFunction
--import Control.Arrow (arr)

import FnReps.Polynomial.UnaryCheb.Poly.Basics
import FnReps.Polynomial.UnaryCheb.Poly.EvaluationRootFinding (shiftDomainBy)
import FnReps.Polynomial.UnaryCheb.Poly.Cheb2Power (cheb2Power)
import FnReps.Polynomial.UnaryCheb.Poly.DCTMultiplication (lift1_DCT)
--import FnReps.Polynomial.UnaryCheb.Poly.Bernstein

import Debug.Trace (trace)


shouldTrace :: Bool
--shouldTrace = False
shouldTrace = True

maybeTrace :: String -> a -> a
maybeTrace 
    | shouldTrace = trace
    | otherwise = const id


{-
    The following functions test sqrtAbsX over the domain [-1,2].
    
    Result accuracy and sample run-time measurements:
    
        * d=8, p=100: eps=0.66... computed in 0.5s
        * d=16, p=100: eps=0.45... computed in 1.5s
        * d=32, p=300: eps=0.30... computed in 26s
-}

{-
    The key polynomials computed by _sqrtAbsX8
    are plotted in http://fooplot.com/plot/d41cy0ouxp.
-}
_sqrtAbsX8 :: Poly
_sqrtAbsX8 = sqrtAbsX (prec 100) 7 (Interval (-1.0) 2.0)

_sqrtAbsX16 :: Poly
_sqrtAbsX16 = sqrtAbsX (prec 100) 15 (Interval (-1.0) 2.0)

_sqrtAbsX32 :: Poly
_sqrtAbsX32 = sqrtAbsX (prec 300) 31 (Interval (-1.0) 2.0)

_sqrtAbsX64 :: Poly
_sqrtAbsX64 = sqrtAbsX (prec 500) 63 (Interval (-1.0) 2.0)
    
sqrtAbsX :: Precision -> Integer -> Interval Rational -> Poly
sqrtAbsX p d (Interval l r) 
    | 0 <= l = 
        error "sqrtAbsX should be called over a domain that contains 0 in its interior"
    | r <= 0 =
        error "sqrtAbsX should be called over a domain that contains 0 in its interior"
    | otherwise =
        maybeTrace
        (
            "sqrtAbsX:"
            ++ "\n zeroPoint = " ++ show zeroPoint
            ++ "\n targetEps = " ++ showB targetEps
            ++ "\n sqrtPos = " ++ showAP sqrtPos
            ++ "\n sqrtNeg = " ++ showAP sqrtNeg
            ++ "\n sqrtPos^2 = " ++ (showAP $ sqrtPos * sqrtPos)
            ++ "\n sqrtNeg^2 = " ++ (showAP $ sqrtNeg * sqrtNeg)
            ++ "\n sqrtPosSquareE = " ++ showB sqrtPosSquareE
            ++ "\n sqrtNegSquareE = " ++ showB sqrtNegSquareE
            ++ "\n epsilonPos = " ++ showQ epsilonPos
            ++ "\n epsilonPos2 = " ++ showQ epsilonPos2
            ++ "\n sqrtPosZRangeL = " ++ showB sqrtPosZRangeL
            ++ "\n sqrtPosZRangeR = " ++ showB sqrtPosZRangeR
            ++ "\n sqrtPosE = " ++ showB sqrtPosE
            ++ "\n epsilonNeg = " ++ showQ epsilonNeg
            ++ "\n epsilonNeg2 = " ++ showQ epsilonNeg2
            ++ "\n sqrtNegZRangeL = " ++ showB sqrtNegZRangeL
            ++ "\n sqrtNegZRangeR = " ++ showB sqrtNegZRangeR
            ++ "\n sqrtNegE = " ++ showB sqrtNegE
            ++ "\n errorBoundPosC = " ++ showB errorBoundPosC
            ++ "\n errorBoundNegC = " ++ showB errorBoundNegC
            ++ "\n errorBoundPos = " ++ showB errorBoundPos
            ++ "\n errorBoundNeg = " ++ showB errorBoundNeg
            ++ "\n resC = " ++ showAP resC
        ) $ 
        res
    where
    showB = show . getApproximate (bits 30)
    showQ = showB . mpBall
    showAP = show . getApproximate (bits 50) . cheb2Power
    
    -- the result polynomial enclosure
    res = Poly $ terms_updateConst pmErrorBound resCTerms
        where 
        pmErrorBound c = endpoints2Ball (c - errorBound) (c + errorBound)
        errorBound = max errorBoundPos errorBoundNeg
    resC@(Poly resCTerms) = lift1_DCT (const d) (\b -> sqrt (abs b)) x
    targetEps = ballCentre $ (evalAtDomPointUnaryFnA (resC, zeroPoint)) / 100
    
    -- x over interval [l,r] scaled to the domain [-1,1]
    x :: Poly
    x = 
        setPrecision_poly p $ 
            normaliseCoeffs $ fromList [(0,a0),(1,a1)]
        where
        a1 = rational2BallP p $ (r-l)/2
        a0 = rational2BallP p $ (r+l)/2
    -- the point in [-1,1] that maps to 0 in [l,r] 
    zeroPoint = -(r+l)/(r-l)
    

    -- approximations of sqrt(x) and sqrt(-x) on the two halves around zeroPoint    
    sqrtPos = 
        shiftDomainBy (2*l/(r-l)) $ 
            lift1_DCT (const (floor $ d / 2)) (\b -> (sqrt(max (targetEps/16) b))) (x - l)
    sqrtNeg = 
        shiftDomainBy (2*r/(r-l)) $ 
            lift1_DCT (const (floor $ d / 2)) (\b -> (sqrt(max (targetEps/16) (-b)))) (x - r)
    -- the error of the square of the above approximations    
    Interval _ sqrtPosSquareE =
        abs $ 
            rangeOnIntervalUnaryFnA (sqrtPos * sqrtPos - x, Interval zeroPoint 1.0)
    Interval _ sqrtNegSquareE =
        abs $ 
            rangeOnIntervalUnaryFnA (sqrtNeg * sqrtNeg + x, Interval (-1.0) zeroPoint)
    -- compute an error bound to sqrtPos and sqrtNeg:
    -- sqrt of the above error ranges gives an epsilon value to aim at:
    epsilonPos = toRationalUp $ sqrt sqrtPosSquareE
    epsilonNeg = toRationalUp $ sqrt sqrtNegSquareE
    {- 
       These epsilons are valid error estimates for sqrtPos, sqrtNeg except near 0,
       more precisely outside the interval [zeroPoint-epsilonNeg^2, zeroPoint+epsilonPos^2]. 
    -}
    epsilonPos2 = epsilonPos * epsilonPos
    epsilonNeg2 = epsilonNeg * epsilonNeg
    Interval sqrtPosZRangeL sqrtPosZRangeR =
        rangeOnIntervalUnaryFnA (sqrtPos, Interval zeroPoint (zeroPoint + epsilonPos2))
    Interval sqrtNegZRangeL sqrtNegZRangeR =
        rangeOnIntervalUnaryFnA (sqrtNeg, Interval (zeroPoint - epsilonNeg2) zeroPoint)
    -- putting error estimates from 2 different regions together, we get error bounds for sqrtPos and sqrtNeg:
    sqrtPosE = foldl1 max [sqrtPosZRangeR, epsilonPos - sqrtPosZRangeL, mpBall epsilonPos]
    sqrtNegE = foldl1 max [sqrtNegZRangeR, epsilonNeg - sqrtNegZRangeL, mpBall epsilonNeg]
    
    Interval _ errorBoundPosC =
        abs $
            rangeOnIntervalUnaryFnA (sqrtPos - resC, Interval zeroPoint 1.0)
    Interval _ errorBoundNegC =
        abs $
            rangeOnIntervalUnaryFnA (sqrtNeg - resC, Interval (-1.0) zeroPoint)
    errorBoundPos = sqrtPosE + errorBoundPosC
    errorBoundNeg = sqrtNegE + errorBoundNegC

{-
    The following is plotted for d=8, 16 and 32 at:
    http://fooplot.com/plot/omp15b3brz
-}
{-
_sqrtAbsXDCT :: Integer -> Poly
_sqrtAbsXDCT d = r
    where
    r = lift1_DCT (const d) (\b -> sqrt (abs b)) x 
    x :: Poly
    x = setPrecision_poly (prec 100) $ projUnaryFnA (Interval (-1.0) 1.0) :: Poly
-}
{-
    The following is plotted for d=8, 16, 32 and 64 at:
    http://fooplot.com/plot/demhnuwnms
-}
{-
_sqrtAbsXBernstein :: Integer -> Poly
_sqrtAbsXBernstein d = bernsteinApprox (prec 200) d (\b -> sqrt(abs b))
-}

_absX8 :: Poly
_absX8 = absX (prec 100) 7 (Interval (-1.0) 2.0)

_absX16 :: Poly
_absX16 = absX (prec 100) 15 (Interval (-1.0) 2.0)

_absX32 :: Poly
_absX32 = absX (prec 300) 31 (Interval (-1.0) 2.0)

absX :: Precision -> Integer -> Interval Rational -> Poly
absX p d (Interval l r) 
    | 0 <= l = 
        error "absX should be called over a domain that contains 0 in its interior"
    | r <= 0 =
        error "absX should be called over a domain that contains 0 in its interior"
    | otherwise =
        maybeTrace
        (
            "sqrtAbsX:"
            ++ "\n zeroPoint = " ++ show zeroPoint
            ++ "\n errorBoundPos = " ++ showB errorBoundPos
            ++ "\n errorBoundNeg = " ++ showB errorBoundNeg
            ++ "\n resC = " ++ showAP resC
        ) $ 
        res
    where
    showB = show . getApproximate (bits 30)
    showAP = show . getApproximate (bits 50) . cheb2Power

    res = Poly $ terms_updateConst pmErrorBound resCTerms
        where 
        pmErrorBound c = endpoints2Ball (c - errorBound) (c + errorBound)
        errorBound = max errorBoundPos errorBoundNeg
    resC@(Poly resCTerms) = lift1_DCT (const d) (\b -> abs b) x
    -- x over interval [l,r] scaled to the domain [-1,1]
    x :: Poly
    x = 
        setPrecision_poly p $ 
            normaliseCoeffs $ fromList [(0,a0),(1,a1)]
        where
        a1 = rational2BallP p $ (r-l)/2
        a0 = rational2BallP p $ (r+l)/2
    -- the point in [-1,1] that maps to 0 in [l,r] 
    zeroPoint = -(r+l)/(r-l)
    
    Interval _ errorBoundPos = 
        abs $
            rangeOnIntervalUnaryFnA (resC - x, Interval zeroPoint (1.0))
    Interval _ errorBoundNeg = 
        abs $
            rangeOnIntervalUnaryFnA (resC + x, Interval (-1.0) zeroPoint)

