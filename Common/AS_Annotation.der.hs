
{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, Christian Maeder, and Uni Bremen 2002-2003
Licence     :  All rights reserved.

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

   These datastructures describe the Annotations of (Het)CASL. 
   There is also a paramterized data type for an 'Annoted' 'item'.

-}

module Common.AS_Annotation where
import Common.Id

-- DrIFT command
{-! global: UpPos !-}

-- | start of an annote with its WORD or a comment
data Annote_word = Annote_word String | Comment_start deriving (Show, Eq)

-- | line or group for 'Unparsed_anno' 
data Annote_text = Line_anno String | Group_anno [String] deriving (Show, Eq)

-- | formats to be displayed (may be extended in the future).
-- Drop 3 from the show result to get the string for parsing and printing  
data Display_format = DF_HTML | DF_LATEX | DF_RTF
		     deriving (Show, Eq, Ord)

-- | swap a pair
swap :: (a, b) -> (b, a)
swap (a, b) = (b, a)

-- | swap the entries of a lookup table
swapTable :: [(a, b)] -> [(b, a)]
swapTable = map swap

-- | drop the first 3 characters from the show result
toTable :: (Show a) => [a] -> [(a, String)]
toTable = map $ \a -> (a, drop 3 $ show a)

-- | a lookup table for the textual representation of display formats
display_format_table :: [(Display_format, String)]
display_format_table = toTable [ DF_HTML, DF_LATEX, DF_RTF ]

-- | precedence 'Lower' means less and 'BothDirections' means less and greater.
-- 'Higher' means greater but this is syntactically not allowed in 'Prec_anno'.
-- 'NoDirection' can also not be specified explicitly,
-- but covers those ids that are not mentionend in precedences.
data PrecRel = Higher | Lower | BothDirections | NoDirection 
	       deriving (Show, Eq)

-- | either left or right associative 
data AssocEither = ALeft | ARight deriving (Show,Eq)

-- | semantic (line) annotations without further information. 
-- Use the same drop-3-trick as for the 'Display_format'.
data Semantic_anno = SA_cons | SA_def | SA_implies | SA_mono | SA_implied
		     deriving (Show, Eq)

-- | a lookup table for the textual representation of semantic annos
semantic_anno_table :: [(Semantic_anno, String)]
semantic_anno_table = toTable [SA_cons, SA_def, 
			       SA_implies, SA_mono, SA_implied]


-- | all possible annotations (without comment-outs)
data Annotation = -- | constructor for comments or unparsed annotes
                Unparsed_anno Annote_word Annote_text [Pos]
		-- | known annotes
		| Display_anno Id [(Display_format, String)] [Pos]
		-- postion of anno start, keywords and anno end
		| List_anno Id Id Id [Pos] 
		-- postion of anno start, commas and anno end
		| Number_anno Id [Pos] 
		-- postion of anno start, commas and anno end
		| Float_anno Id Id [Pos] 
		-- postion of anno start, commas and anno end
		| String_anno Id Id [Pos] 
		-- postion of anno start, commas and anno end
		| Prec_anno PrecRel [Id] [Id] [Pos] 
		--          ^ positions: "{",commas,"}", RecRel, "{",commas,"}"
		--          | Lower = "< "  BothDirections = "<>"
		| Assoc_anno AssocEither [Id] [Pos] -- position of commas
		| Label [String] [Pos] 
		-- postion of anno start and anno end

		-- All annotations below are only as annote line allowed
		| Semantic_anno Semantic_anno [Pos] 
		-- position information for annotations is provided 
		-- by every annotation
		  deriving (Show)


instance Eq Annotation where
      Unparsed_anno aw1 at1 _ == Unparsed_anno aw2 at2 _
	  = (aw1,at1)==(aw2,at2) 
      Display_anno i1 x1 _ == Display_anno i2 x2 _ 
	  = (i1,x1)==(i2,x2) 
      List_anno i1 i2 i3 _ == List_anno i4 i5 i6 _ 
	  = (i1,i2,i3)==(i4,i5,i6)
      Number_anno i1 _ == Number_anno i2 _ 
	  = i1==i2
      Float_anno  i1 i2 _ == Float_anno i3 i4 _ 
	  = (i1,i2)==(i3,i4)
      String_anno i1 i2 _ == String_anno i3 i4 _ 
	  = (i1,i2)==(i3,i4)
      Prec_anno pr1 i1 i2 _ == Prec_anno pr2 i3 i4 _ 
	  = (pr1,i1,i2)==(pr2,i3,i4)
      Assoc_anno ae1 i1 _ == Assoc_anno ae2 i2 _
	  = (ae1,i1) == (ae2,i2)
      Label str1 _ == Label str2 _
	  = str1 == str2
      Semantic_anno sa1 _ == Semantic_anno sa2 _ 
	  = sa1 == sa2 
      _ == _ = False

-- | 
-- 'isLabel' tests if the given 'Annotation' is a label
-- (a 'Label' typically follows a formula)
isLabel :: Annotation -> Bool
isLabel a = case a of
	    Label _ _ -> True
	    _         -> False
isImplied :: Annotation -> Bool
isImplied a =
    case  a of
    Semantic_anno SA_implied _  -> True
    Semantic_anno _ _  -> False
    _ -> False

-- | 
-- 'isSemanticAnno' tests if the given 'Annotation' is a semantic one
isSemanticAnno :: Annotation -> Bool
isSemanticAnno a = case a of
		   Semantic_anno _ _  -> True
		   _ -> False

-- |  
-- 'isComment' tests if the given 'Annotation' is a comment line or a
-- comment group
isComment :: Annotation -> Bool
isComment c = case c of
	      Unparsed_anno Comment_start _ _ -> True
	      _ -> False

-- |
-- 'isAnnote' is the invers function to 'isComment'
isAnnote :: Annotation -> Bool
isAnnote = not . isComment

-- | an item wrapped in preceeding (left 'l_annos') 
-- and following (right 'r_annos') annotations.
-- 'opt_pos' should carry the position of an optional semicolon
-- following a formula (but is currently unused).
data Annoted a = Annoted { item::a, opt_pos :: [Pos]
			 , l_annos, r_annos::[Annotation]}
		 deriving (Show, Eq) 

-- | process all items and wrap matching annotations around the results 
mapAnM :: (Monad m) => (a -> m b) -> [Annoted a] -> m [Annoted b]
mapAnM f al = 
    do il <- mapM (f . item) al
       return $ zipWith ( \ a i -> a { item = i }) al il
		
-- | replace the 'item'
replaceAnnoted :: b -> Annoted a -> Annoted b
replaceAnnoted x (Annoted _ o l r) = Annoted x o l r

-- | add further following annotations
appendAnno :: Annoted a -> [Annotation] -> Annoted a
appendAnno (Annoted x p l r) y = Annoted x p l (r++y)

-- | put together preceding annotations and an item
addLeftAnno :: [Annotation] -> a -> Annoted a
addLeftAnno l i = Annoted i [] l []

-- | get the label following (or to the right of) an 'item'
getRLabel :: Annoted a -> String
getRLabel a = let ls = filter isLabel (r_annos a) in
		  if null ls then "" else 
		     let Label l _ = head ls 
			 in if null l then "" else head l
			    -- might be a multiline label
                            -- maybe remove white spaces
