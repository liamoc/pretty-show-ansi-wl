--------------------------------------------------------------------------------
-- |
-- Module      :  Text.Show.Pretty
-- Copyright   :  (c) Iavor S. Diatchki 2009
-- License     :  MIT
--
-- Maintainer  :  iavor.diatchki@gmail.com
-- Stability   :  provisional
-- Portability :  Haskell 98
--
-- Functions for human-readable derived 'Show' instances.
--------------------------------------------------------------------------------

{-# LANGUAGE CPP #-}
{-# LANGUAGE Safe #-}
module Text.Show.Pretty
  ( -- * Generic representation of values
    Value(..), Name
  , valToStr
  , valToDoc

    -- * Values using the 'Show' class
  , parseValue, reify, ppDoc, ppShow, pPrint

  , -- * Working with listlike ("foldable") collections
    ppDocList, ppShowList, pPrintList

  , -- * Preprocessing of values
    PreProc(..), ppHide, ppHideNested, hideCon

  ) where

import qualified Text.Show.Parser as P
import Text.Show.Value
import Data.Foldable(Foldable,toList)
import Language.Haskell.Lexer(rmSpace,lexerPass0)
import Text.PrettyPrint.ANSI.Leijen hiding (hang)
import Prelude hiding ( (<>) )


hang :: Doc -> Int -> Doc -> Doc
hang d1 n d2 = sep [d1, nest n d2]

reify :: Show a => a -> Maybe Value
reify = parseValue . show

parseValue :: String -> Maybe Value
parseValue = P.parseValue . rmSpace . lexerPass0

-- | Convert a generic value into a pretty 'String', if possible.
ppShow :: Show a => a -> String
ppShow = show . ppDoc

-- | Pretty print something that may be converted to a list as a list.
-- Each entry is on a separate line, which means that we don't do clever
-- pretty printing, and so this works well for large strucutures.
ppShowList :: (Foldable f, Show a) => f a -> String
ppShowList = show . ppDocList

-- | Try to show a value, prettily. If we do not understand the value, then we
--   just use its standard 'Show' instance.
ppDoc :: Show a => a -> Doc
ppDoc a = case parseValue txt of
            Just v  -> valToDoc v
            Nothing -> text txt
  where txt = show a

-- | Pretty print something that may be converted to a list as a list.
-- Each entry is on a separate line, which means that we don't do clever
-- pretty printing, and so this works well for large strucutures.
ppDocList :: (Foldable f, Show a) => f a -> Doc
ppDocList = blockWith vcat '[' ']' . map ppDoc . toList

-- | Pretty print a generic value to stdout. This is particularly useful in the
-- GHCi interactive environment.
pPrint :: Show a => a -> IO ()
pPrint = putStrLn . ppShow

-- | Pretty print something that may be converted to a list as a list.
-- Each entry is on a separate line, which means that we don't do clever
-- pretty printing, and so this works well for large strucutures.
pPrintList :: (Foldable f, Show a) => f a -> IO ()
pPrintList = putStrLn . ppShowList

-- | Pretty print a generic value. Our intention is that the result is
--   equivalent to the 'Show' instance for the original value, except possibly
--   easier to understand by a human.
valToStr :: Value -> String
valToStr = show . valToDoc

-- | Pretty print a generic value. Our intention is that the result is
--   equivalent to the 'Show' instance for the original value, except possibly
--   easier to understand by a human.
valToDoc :: Value -> Doc
valToDoc val = case val of
  Con c vs         -> ppCon c vs
  InfixCons v1 cvs -> hang_sep (go v1 cvs)
    where
      go v []            = [ppInfixAtom v]
      go v ((n,v2):cvs') = (ppInfixAtom v <+> text n):go v2 cvs'

      hang_sep [] = empty
      hang_sep (x:xs) = hang x 2 (sep xs)
    -- hang (ppInfixAtom v1) 2 (sep [ text n <+> ppInfixAtom v | (n,v) <- cvs ])
  Rec c fs         -> hang (text c) 2 $ block '{' '}' (map ppField fs)
    where ppField (x,v) = hang (text x <+> char '=') 2 (valToDoc v)

  List vs          -> block '[' ']' (map valToDoc vs)
  Tuple vs         -> block '(' ')' (map valToDoc vs)
  Neg v            -> char '-' <> ppAtom v
  Ratio x y        -> hang (ppAtom x <+> text "%") 2 (ppAtom y)
  Integer x        -> text x
  Float x          -> text x
  Char x           -> text x
  String x         -> text x


-- | This type is used to allow pre-processing of values before showing them.
data PreProc a = PreProc (Value -> Value) a

instance Show a => Show (PreProc a) where
  showsPrec p (PreProc f a) cs =
    case parseValue txt of
      Nothing -> txt ++ cs
      Just v  -> wrap (valToStr (f v))
    where
    txt    = showsPrec p a ""
    wrap t = case (t,txt) of
              (h:_,'(':_) | h /= '(' -> '(' : (t ++ ')' : cs)
              _ -> t ++ cs

-- | Hide the given constructors when showing a value.
ppHide :: (Name -> Bool) -> a -> PreProc a
ppHide p = PreProc (hideCon False p)

-- | Hide the given constructors when showing a value.
-- In addition, hide values if all of their children were hidden.
ppHideNested :: (Name -> Bool) -> a -> PreProc a
ppHideNested p = PreProc (hideCon True p)



-- Private ---------------------------------------------------------------------

ppAtom :: Value -> Doc
ppAtom v
  | isAtom v  = valToDoc v
  | otherwise = parens (valToDoc v)

ppInfixAtom :: Value -> Doc
ppInfixAtom v
  | isInfixAtom v = valToDoc v
  | otherwise     = parens (valToDoc v)

ppCon :: Name -> [Value] -> Doc
ppCon "" vs = sep (map ppAtom vs)
ppCon c vs  = hang (text c) 2 (sep (map ppAtom vs))

isAtom               :: Value -> Bool
isAtom (Con _ (_:_))  = False
isAtom (InfixCons {}) = False
isAtom (Ratio {})     = False
isAtom (Neg {})       = False
isAtom _              = True

-- Don't put parenthesis around constructors in infix chains
isInfixAtom          :: Value -> Bool
isInfixAtom (InfixCons {}) = False
isInfixAtom (Ratio {})     = False
isInfixAtom (Neg {})       = False
isInfixAtom _              = True

block :: Char -> Char -> [Doc] -> Doc
block = blockWith sep

blockWith :: ([Doc] -> Doc) -> Char -> Char -> [Doc] -> Doc
blockWith _ a b []      = char a <> char b
blockWith f a b (d:ds)  = f $
    (char a <+> d) : [ char ',' <+> x | x <- ds ] ++ [ char b ]



