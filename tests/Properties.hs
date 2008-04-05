{-# OPTIONS_GHC -fno-warn-orphans -fno-warn-missing-methods #-}
module Properties (main) where
import Network.MPD.Utils
import Network.MPD.Parse

import Control.Monad
import Data.Char
import Data.List
import Data.Maybe
import System.Environment
import Text.Printf
import Test.QuickCheck

main :: IO ()
main = do
    n <- (maybe 100 read . listToMaybe) `liftM` getArgs
    mapM_ (\(s, f) -> printf "%-25s : " s >> f n) tests
    where tests = [("splitGroups / reversible",
                        mytest prop_splitGroups_rev)
                  ,("splitGroups / integrity",
                        mytest prop_splitGroups_integrity)
                  ,("parseBool", mytest prop_parseBool)
                  ,("parseBool / reversible",
                        mytest prop_parseBool_rev)
                  ,("showBool", mytest prop_showBool)
                  ,("toAssoc / reversible",
                        mytest prop_toAssoc_rev)
                  ,("toAssoc / integrity",
                        mytest prop_toAssoc_integrity)
                  ,("parseNum", mytest prop_parseNum)
                  ,("parseDate / simple",
                        mytest prop_parseDate_simple)
                  ,("parseDate / complex",
                        mytest prop_parseDate_complex)
                  ,("parseCount", mytest prop_parseCount)]

mytest :: Testable a => a -> Int -> IO ()
mytest a n = check defaultConfig { configMaxTest = n } a

instance Arbitrary Char where
    arbitrary     = choose ('\0', '\128')

-- an assoc. string is a string of the form "key: value".
newtype AssocString = AS String
    deriving Show

instance Arbitrary AssocString where
    arbitrary = do
        key <- arbitrary
        val <- arbitrary
        return . AS $ key ++ ": " ++ val

newtype IntegralString = IS String
    deriving Show

instance Arbitrary IntegralString where
    arbitrary = fmap (IS . show) (arbitrary :: Gen Integer)

newtype BoolString = BS String
    deriving Show

instance Arbitrary BoolString where
    arbitrary = fmap BS $ oneof [return "1", return "0"]

-- Positive integers.
newtype PosInt = PI Integer

instance Show PosInt where
    show (PI x) = show x

instance Arbitrary PosInt where
    arbitrary = (PI . abs) `fmap` arbitrary

-- Simple date representation, like "2004" and "1998".
newtype SimpleDateString = SDS String
    deriving Show

instance Arbitrary SimpleDateString where
    arbitrary = (SDS . show) `fmap` (arbitrary :: Gen PosInt)

-- Complex date representations, like "2004-20-30".
newtype ComplexDateString = CDS String
    deriving Show

instance Arbitrary ComplexDateString where
    arbitrary = do
        -- eww...
        [y,m,d] <- replicateM 3 (arbitrary :: Gen PosInt)
        return . CDS . intercalate "-" $ map show [y,m,d]

prop_parseDate_simple :: SimpleDateString -> Bool
prop_parseDate_simple (SDS x) = isJust $ parseDate x

prop_parseDate_complex :: ComplexDateString -> Bool
prop_parseDate_complex (CDS x) = isJust $ parseDate x

prop_toAssoc_rev :: [AssocString] -> Bool
prop_toAssoc_rev x = toAssoc (fromAssoc r) == r
    where r = toAssoc (fromAS x)
          fromAssoc = map (\(a, b) -> a ++ ": " ++ b)

prop_toAssoc_integrity :: [AssocString] -> Bool
prop_toAssoc_integrity x = length (toAssoc $ fromAS x) == length x

fromAS :: [AssocString] -> [String]
fromAS s = [x | AS x <- s]

prop_parseBool_rev :: BoolString -> Bool
prop_parseBool_rev (BS x) = showBool (fromJust $ parseBool x) == x

prop_parseBool :: BoolString -> Bool
prop_parseBool (BS "1") = fromJust $ parseBool "1"
prop_parseBool (BS x)   = not (fromJust $ parseBool x)

prop_showBool :: Bool -> Bool
prop_showBool True = showBool True == "1"
prop_showBool x    = showBool x == "0"

prop_splitGroups_rev :: [(String, String)] -> Property
prop_splitGroups_rev xs = not (null xs) ==>
    let wrappers = [(fst $ head xs, id)]
        r = splitGroups wrappers xs
    in r == splitGroups wrappers (concat r)

prop_splitGroups_integrity :: [(String, String)] -> Property
prop_splitGroups_integrity xs = not (null xs) ==>
    sort (concat $ splitGroups [(fst $ head xs, id)] xs) == sort xs

prop_parseNum :: IntegralString -> Bool
prop_parseNum (IS xs@"")      = parseNum xs == Nothing
prop_parseNum (IS xs@('-':_)) = fromMaybe 0 (parseNum xs) <= 0
prop_parseNum (IS xs)         = fromMaybe 0 (parseNum xs) >= 0


--------------------------------------------------------------------------
-- Parsers
--------------------------------------------------------------------------

-- | A uniform interface for types that
-- can be turned into raw responses
class Displayable a where
    empty   :: a             -- ^ An empty instance
    display :: a -> String   -- ^ Transform instantiated object to a
                             --   string

instance Displayable Count where
    empty = Count { cSongs = 0, cPlaytime = 0 }
    display s = unlines $
        ["songs: "    ++ show (cSongs s)
        ,"playtime: " ++ show (cPlaytime s)]

instance Arbitrary Count where
    arbitrary = do
        songs <- arbitrary
        time  <- arbitrary
        return $ Count { cSongs = songs, cPlaytime = time }

prop_parseCount :: Count -> Bool
prop_parseCount c = Right c == (parseCount . lines $ display c)
