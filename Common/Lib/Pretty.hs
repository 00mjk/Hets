{- |
Module      :  $Header$
Description :  John Hughes's and Simon Peyton Jones's Pretty Printer Combinators
Copyright   :  (c) Hughes, Peyton Jones, K. L�ttich, C. Maeder 1996-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

John Hughes's and Simon Peyton Jones's Pretty Printer Combinators
   with modifications marked with 'added by KL'

   Based on /The Design of a Pretty-printing Library/
   in Advanced Functional Programming,
   Johan Jeuring and Erik Meijer (eds), LNCS 925
   <http://www.cs.chalmers.se/~rjmh/Papers/pretty.ps>

   Heavily modified by Simon Peyton Jones, Dec 96
-}

{-
Version 3.0     28 May 1997
  * Cured massive performance bug.  If you write

        foldl <> empty (map (text.show) [1..10000])

    you get quadratic behaviour with V2.0.  Why?  For just the same
    reason as you get quadratic behaviour with left-associated (++)
    chains.

    This is really bad news.  One thing a pretty-printer abstraction
    should certainly guarantee is insensivity to associativity.  It
    matters: suddenly GHC's compilation times went up by a factor of
    100 when I switched to the new pretty printer.

    I fixed it with a bit of a hack (because I wanted to get GHC back
    on the road).  I added two new constructors to the Doc type, Above
    and Beside:

         <> = Beside
         $$ = Above

    Then, where I need to get to a "TextBeside" or "NilAbove" form I
    "force" the Doc to squeeze out these suspended calls to Beside and
    Above; but in so doing I re-associate. It's quite simple, but I'm
    not satisfied that I've done the best possible job.  I'll send you
    the code if you are interested.

  * Added new exports:
        punctuate, hang
        int, integer, float, double, rational,
        lparen, rparen, lbrack, rbrack, lbrace, rbrace,

  * fullRender's type signature has changed.  Rather than producing a
    string it now takes an extra couple of arguments that tells it how
    to glue fragments of output together:

        fullRender :: Mode
                   -> Int                       -- Line length
                   -> Float                     -- Ribbons per line
                   -> (TextDetails -> a -> a)   -- What to do with text
                   -> a                         -- What to do at the end
                   -> Doc
                   -> a                         -- Result

    The "fragments" are encapsulated in the TextDetails data type:

        data TextDetails = Chr  Char
                         | Str  String
                         | PStr FAST_STRING

    The Chr and Str constructors are obvious enough.  The PStr
    constructor has a packed string (FAST_STRING) inside it.  It's
    generated by using the new "ptext" export.

    An advantage of this new setup is that you can get the renderer to
    do output directly (by passing in a function of type (TextDetails
    -> IO () -> IO ()), rather than producing a string that you then
    print.


Version 2.0     24 April 1997
  * Made empty into a left unit for <> as well as a right unit;
    it is also now true that
        nest k empty = empty
    which wasn't true before.

  * Fixed an obscure bug in sep that occassionally gave very weird behaviour

  * Added $+$

  * Corrected and tidied up the laws and invariants

======================================================================
Relative to John's original paper, there are the following new features:

1.  There's an empty document, "empty".  It's a left and right unit for
    both <> and $$, and anywhere in the argument list for
    sep, hcat, hsep, vcat, fcat etc.

    It is Really Useful in practice.

2.  There is a paragraph-fill combinator, fsep, that's much like sep,
    only it keeps fitting things on one line until it can't fit any more.

3.  Some random useful extra combinators are provided.
        <+> puts its arguments beside each other with a space between them,
            unless either argument is empty in which case it returns the other


        hcat is a list version of <>
        hsep is a list version of <+>
        vcat is a list version of $+$

        sep (separate) is either like hsep or like vcat, depending on what fits

        cat  behaves like sep,  but it uses <> for horizontal conposition
        fcat behaves like fsep, but it uses <> for horizontal conposition

        These new ones do the obvious things:
                char, semi, comma, colon, space,
                parens, brackets, braces,
                quotes, doubleQuotes

4.  The "above" combinator, $$, now overlaps its two arguments if the
    last line of the top argument stops before the first line of the
    second begins.

        For example:  text "hi" $$ nest 5 "there"
        lays out as
                        hi   there
        rather than
                        hi
                             there

        There are two places this is really useful

        a) When making labelled blocks, like this:
                Left ->   code for left
                Right ->  code for right
                LongLongLongLabel ->
                          code for longlonglonglabel
           The block is on the same line as the label if the label is
           short, but on the next line otherwise.

        b) When laying out lists like this:
                [ first
                , second
                , third
                ]
           which some people like.  But if the list fits on one line
           you want [first, second, third].  You can't do this with
           John's original combinators, but it's quite easy with the
           new $$.

        The combinator $+$ gives the original "never-overlap" behaviour.

5.      Several different renderers are provided:
        * a standard one
        * one that uses cut-marks to avoid deeply-nested documents
                        simply piling up in the right-hand margin
        * one that ignores indentation (fewer chars output; good for machines)
        * one that ignores indentation and newlines (ditto, only more so)

6.      Numerous implementation tidy-ups
        Use of unboxed data types to speed up the implementation
-}

module Common.Lib.Pretty (

        -- * The document type
        Doc,            -- Abstract

        -- * Primitive Documents
        empty,
        semi, comma, colon, space, equals,
        lparen, rparen, lbrack, rbrack, lbrace, rbrace,

        -- * Converting values into documents
        text, char, ptext, sp_text,
        int, integer, float, double, rational,

        -- * Wrapping documents in delimiters
        parens, brackets, braces, quotes, doubleQuotes,

        -- * Combining documents
        (<>), (<+>), hcat, hsep,
        ($$), ($+$), vcat,
        sep, cat,
        fsep, fcat,
        nest,
        hang, punctuate,

        -- * Predicates on documents
        isEmpty,

        -- * Rendering documents

        -- ** Default rendering
        render,

        -- ** Rendering with a particular style
        Style(..),
        style,
        renderStyle,
        renderStyle',

        -- ** General rendering
        fullRender,
        Mode(..),
        TextDetails(..)
                       ) where

import Prelude

infixl 6 <>
infixl 6 <+>
infixl 5 $$, $+$

-- ---------------------------------------------------------------------------
-- The interface

-- The primitive Doc values

isEmpty :: Doc    -> Bool;  -- ^ Returns 'True' if the document is empty

empty   :: Doc;                 -- ^ An empty document
semi    :: Doc;                 -- ^ A ';' character
comma   :: Doc;                 -- ^ A ',' character
colon   :: Doc;                 -- ^ A ':' character
space   :: Doc;                 -- ^ A space character
equals  :: Doc;                 -- ^ A '=' character
lparen  :: Doc;                 -- ^ A '(' character
rparen  :: Doc;                 -- ^ A ')' character
lbrack  :: Doc;                 -- ^ A '[' character
rbrack  :: Doc;                 -- ^ A ']' character
lbrace  :: Doc;                 -- ^ A '{' character
rbrace  :: Doc;                 -- ^ A '}' character

text     :: String   -> Doc
ptext    :: String   -> Doc
-- added by KL
{- |
the conversion function @sp_text@ can be used for a special use of this
library. This function enables the possibility to use the rendering
alghorithms provided for rendering LaTeX with a proportional font. It
can also be abused because you can add text that has a zero width.
-}
sp_text  :: Int -> String -> Doc
char     :: Char     -> Doc
int      :: Int      -> Doc
integer  :: Integer  -> Doc
float    :: Float    -> Doc
double   :: Double   -> Doc
rational :: Rational -> Doc


parens       :: Doc -> Doc;     -- ^ Wrap document in @(...)@
brackets     :: Doc -> Doc;     -- ^ Wrap document in @[...]@
braces       :: Doc -> Doc;     -- ^ Wrap document in @{...}@
quotes       :: Doc -> Doc;     -- ^ Wrap document in @\'...\'@
doubleQuotes :: Doc -> Doc;     -- ^ Wrap document in @\"...\"@

-- Combining @Doc@ values

(<>)   :: Doc -> Doc -> Doc;     -- ^Beside
hcat   :: [Doc] -> Doc;          -- ^List version of '<>'
(<+>)  :: Doc -> Doc -> Doc;     -- ^Beside, separated by space
hsep   :: [Doc] -> Doc;          -- ^List version of '<+>'

($$)   :: Doc -> Doc -> Doc;     -- ^Above; if there is no
                                -- overlap it \"dovetails\" the two
($+$)   :: Doc -> Doc -> Doc;    -- ^Above, without dovetailing.
vcat   :: [Doc] -> Doc;          -- ^List version of '$+$'

cat    :: [Doc] -> Doc;          -- ^ Either hcat or vcat
sep    :: [Doc] -> Doc;          -- ^ Either hsep or vcat
fcat   :: [Doc] -> Doc;          -- ^ \"Paragraph fill\" version of cat
fsep   :: [Doc] -> Doc;          -- ^ \"Paragraph fill\" version of sep

nest   :: Int -> Doc -> Doc;     -- ^ Nested


-- GHC-specific ones.

hang :: Doc -> Int -> Doc -> Doc   -- ^ @hang d1 n d2 = sep [d1, nest n d2]@
punctuate :: Doc -> [Doc] -> [Doc]
  -- ^ @punctuate p [d1, ... dn] = [d1 \<> p, d2 \<> p, ... dn-1 \<> p, dn]@


-- Displaying @Doc@ values.

instance Show Doc where
  showsPrec _prec doc cont = showDoc doc cont

-- | Renders the document as a string using the default style
render     :: Doc -> String

-- | The general rendering interface
fullRender :: Mode                      -- ^Rendering mode
           -> Int                       -- ^Line length
           -> Float                     -- ^Ribbons per line
           -> (TextDetails -> a -> a)   -- ^What to do with text
           -> a                         -- ^What to do at the end
           -> Doc                       -- ^The document
           -> a                         -- ^Result

-- | Render the document as a string using a specified style
renderStyle  :: Style -> Doc -> String

-- | A rendering style
data Style
 = Style { mode           :: Mode    -- ^ The rendering mode
         , lineLength     :: Int     -- ^ Length of line, in chars
         , ribbonsPerLine :: Float   -- ^ Ratio of ribbon length to line length
         }

-- | The default style (@mode=PageMode, lineLength=80, ribbonsPerLine=1.19@)
style :: Style
style = Style { lineLength = 80, ribbonsPerLine = 1.19, mode = PageMode }
-- maximum line length 80 with 67 printable chars (up to 13 indentation chars)

-- | Rendering mode
data Mode = PageMode            -- ^Normal
          | ZigZagMode          -- ^With zig-zag cuts
          | LeftMode            -- ^No indentation, infinitely long lines
          | OneLineMode         -- ^All on one line

-- ---------------------------------------------------------------------------
-- The Doc calculus

-- The Doc combinators satisfy the following laws:

{-
Laws for $$
~~~~~~~~~~~
<a1>    (x $$ y) $$ z   = x $$ (y $$ z)
<a2>    empty $$ x      = x
<a3>    x $$ empty      = x

        ...ditto $+$...

Laws for <>
~~~~~~~~~~~
<b1>    (x <> y) <> z   = x <> (y <> z)
<b2>    empty <> x      = empty
<b3>    x <> empty      = x

        ...ditto <+>...

Laws for text
~~~~~~~~~~~~~
<t1>    text s <> text t        = text (s++t)
<t2>    text "" <> x            = x, if x non-empty

Laws for nest
~~~~~~~~~~~~~
<n1>    nest 0 x                = x
<n2>    nest k (nest k' x)      = nest (k+k') x
<n3>    nest k (x <> y)         = nest k z <> nest k y
<n4>    nest k (x $$ y)         = nest k x $$ nest k y
<n5>    nest k empty            = empty
<n6>    x <> nest k y           = x <> y, if x non-empty

** Note the side condition on <n6>!  It is this that
** makes it OK for empty to be a left unit for <>.

Miscellaneous
~~~~~~~~~~~~~
<m1>    (text s <> x) $$ y = text s <> ((text "" <> x)) $$
                                         nest (-length s) y)

<m2>    (x $$ y) <> z = x $$ (y <> z)
        if y non-empty


Laws for list versions
~~~~~~~~~~~~~~~~~~~~~~
<l1>    sep (ps++[empty]++qs)   = sep (ps ++ qs)
        ...ditto hsep, hcat, vcat, fill...

<l2>    nest k (sep ps) = sep (map (nest k) ps)
        ...ditto hsep, hcat, vcat, fill...

Laws for oneLiner
~~~~~~~~~~~~~~~~~
<o1>    oneLiner (nest k p) = nest k (oneLiner p)
<o2>    oneLiner (x <> y)   = oneLiner x <> oneLiner y

You might think that the following verion of <m1> would
be neater:

<3 NO>  (text s <> x) $$ y = text s <> ((empty <> x)) $$
                                         nest (-length s) y)

But it doesn't work, for if x=empty, we would have

        text s $$ y = text s <> (empty $$ nest (-length s) y)
                    = text s <> nest (-length s) y
-}

-- ---------------------------------------------------------------------------
-- Simple derived definitions

semi  = char ';'
colon = char ':'
comma = char ','
space = char ' '
equals = char '='
lparen = char '('
rparen = char ')'
lbrack = char '['
rbrack = char ']'
lbrace = char '{'
rbrace = char '}'

int      n = text (show n)
integer  n = text (show n)
float    n = text (show n)
double   n = text (show n)
rational n = text (show n)
-- SIGBJORN wrote instead:
-- rational n = text (show (fromRationalX n))

quotes p        = char '\'' <> p <> char '\''
doubleQuotes p  = char '"' <> p <> char '"'
parens p        = char '(' <> p <> char ')'
brackets p      = char '[' <> p <> char ']'
braces p        = char '{' <> p <> char '}'


hcat = foldr (<>)  empty
hsep = foldr (<+>) empty
vcat = foldr ($+$)  empty

hang d1 n d2 = sep [d1, nest n d2]

punctuate _ []     = []
punctuate p (a:ds) = go a ds
                   where
                     go d [] = [d]
                     go d (e:es) = (d <> p) : go e es

-- ---------------------------------------------------------------------------
-- The Doc data type

-- A Doc represents a *set* of layouts.  A Doc with
-- no occurrences of Union or NoDoc represents just one layout.

-- | The abstract type of documents
data Doc
 = Empty                                -- empty
 | NilAbove Doc                         -- text "" $$ x
 | TextBeside TextDetails !Int Doc      -- text s <> x
 | Nest !Int Doc                        -- nest k x
 | Union Doc Doc                        -- ul `union` ur
 | NoDoc                                -- The empty set of documents
 | Beside Doc Bool Doc                  -- True <=> space between
 | Above  Doc Bool Doc                  -- True <=> never overlap

-- RDoc is a "reduced Doc", guaranteed not to have a top-level Above or Beside
type RDoc = Doc

reduceDoc :: Doc -> RDoc
reduceDoc (Beside p g q) = beside p g (reduceDoc q)
reduceDoc (Above  p g q) = above  p g (reduceDoc q)
reduceDoc p              = p


data TextDetails = Chr  Char
                 | Str  String
                 | PStr String

space_text, nl_text :: TextDetails
space_text = Chr ' '
nl_text    = Chr '\n'

{-
  Here are the invariants:

  * The argument of NilAbove is never Empty. Therefore
    a NilAbove occupies at least two lines.

  * The arugment of @TextBeside@ is never @Nest@.


  * The layouts of the two arguments of @Union@ both flatten to the same
    string.

  * The arguments of @Union@ are either @TextBeside@, or @NilAbove@.

  * The right argument of a union cannot be equivalent to the empty set
    (@NoDoc@).  If the left argument of a union is equivalent to the
    empty set (@NoDoc@), then the @NoDoc@ appears in the first line.

  * An empty document is always represented by @Empty@.  It can't be
    hidden inside a @Nest@, or a @Union@ of two @Empty@s.

  * The first line of every layout in the left argument of @Union@ is
    longer than the first line of any layout in the right argument.
    (1) ensures that the left argument has a first line.  In view of
    (3), this invariant means that the right argument must have at
    least two lines.
-}

        -- Arg of a NilAbove is always an RDoc
nilAbove_ :: Doc -> Doc
nilAbove_ p = NilAbove p

        -- Arg of a TextBeside is always an RDoc
textBeside_ :: TextDetails -> Int -> Doc -> Doc
textBeside_ s sl p = TextBeside s sl p

        -- Arg of Nest is always an RDoc
nest_ :: Int -> Doc -> Doc
nest_ k p = Nest k p

        -- Args of union are always RDocs
union_ :: Doc -> Doc -> Doc
union_ p q = Union p q


-- Notice the difference between
--         * NoDoc (no documents)
--         * Empty (one empty document; no height and no width)
--         * text "" (a document containing the empty string;
--                    one line high, but has no width)


-- ---------------------------------------------------------------------------
-- @empty@, @text@, @nest@, @union@

empty = Empty

isEmpty d = case reduceDoc d of
              Empty -> True
              _ -> False

char  c = textBeside_ (Chr c) 1 Empty
text  s = case length   s of {sl -> textBeside_ (Str s)  sl Empty}
ptext s = case length s of {sl -> textBeside_ (PStr s) sl Empty}
-- added by KL
sp_text sl s = case sl of {sl1 -> textBeside_ (PStr s) sl1 Empty}

nest k  p = mkNest k (reduceDoc p)        -- Externally callable version

-- mkNest checks for Nest's invariant that it doesn't have an Empty inside it
mkNest :: Int -> Doc -> Doc
mkNest k       _           | k `seq` False = (error "Pretty.hs")
mkNest k       (Nest k1 p) = mkNest (k + k1) p
mkNest _       NoDoc       = NoDoc
mkNest _       Empty       = Empty
mkNest 0       p           = p                  -- Worth a try!
mkNest k       p           = nest_ k p

-- mkUnion checks for an empty document
mkUnion :: Doc -> Doc -> Doc
mkUnion Empty _ = Empty
mkUnion p q     = p `union_` q

-- ---------------------------------------------------------------------------
-- Vertical composition @$$@

p $$  q = Above p False q
p $+$ q = Above p True q

above :: Doc -> Bool -> RDoc -> RDoc
above (Above p g1 q1)  g2 q2 = above p g1 (above q1 g2 q2)
above p@(Beside _ _ _) g  q  = aboveNest (reduceDoc p) g 0 (reduceDoc q)
above p g q                  = aboveNest p             g 0 (reduceDoc q)

aboveNest :: RDoc -> Bool -> Int -> RDoc -> RDoc
-- Specfication: aboveNest p g k q = p $g$ (nest k q)

aboveNest _                   _ k _ | k `seq` False = (error "Pretty.hs")
aboveNest NoDoc               _ _ _ = NoDoc
aboveNest (p1 `Union` p2)     g k q = aboveNest p1 g k q `union_`
                                      aboveNest p2 g k q

aboveNest Empty               _ k q = mkNest k q
aboveNest (Nest k1 p)         g k q = nest_ k1 (aboveNest p g (k - k1) q)
                                  -- p can't be Empty, so no need for mkNest

aboveNest (NilAbove p)        g k q = nilAbove_ (aboveNest p g k q)
aboveNest (TextBeside s sl p) g k q = k1 `seq` textBeside_ s sl rest
                                    where
                                      k1   = k - sl
                                      rest = case p of
                                                Empty -> nilAboveNest g k1 q
                                                _     -> aboveNest  p g k1 q
aboveNest _ _ _ _ = error "Common.Lib.Pretty.aboveNest"


nilAboveNest :: Bool -> Int -> RDoc -> RDoc
-- Specification: text s <> nilaboveNest g k q
--              = text s <> (text "" $g$ nest k q)

nilAboveNest _ k _           | k `seq` False = (error "Pretty.hs")
nilAboveNest _ _ Empty       = Empty
        -- Here's why the "text s <>" is in the spec!
nilAboveNest g k (Nest k1 q) = nilAboveNest g (k + k1) q

nilAboveNest g k q           | (not g) && (k > 0) -- No newline if no overlap
                             = textBeside_ (Str (indent k)) k q
                             | otherwise          -- Put them really above
                             = nilAbove_ (mkNest k q)

-- ---------------------------------------------------------------------------
-- Horizontal composition @<>@

p <>  q = Beside p False q
p <+> q = Beside p True  q

beside :: Doc -> Bool -> RDoc -> RDoc
-- Specification: beside g p q = p <g> q

beside NoDoc               _ _   = NoDoc
beside (p1 `Union` p2)     g q   = (beside p1 g q) `union_` (beside p2 g q)
beside Empty               _ q   = q
beside (Nest k p)          g q   = nest_ k (beside p g q)       -- p non-empty
beside p@(Beside p1 g1 q1) g2 q2
           {- (A `op1` B) `op2` C == A `op1` (B `op2` C)  iff op1 == op2
              [ && (op1 == <> || op1 == <+>) ] -}
         | g1 == g2              = beside p1 g1 (beside q1 g2 q2)
         | otherwise             = beside (reduceDoc p) g2 q2
beside p@(Above _ _ _)     g q   = beside (reduceDoc p) g q
beside (NilAbove p)        g q   = nilAbove_ (beside p g q)
beside (TextBeside s sl p) g q   = textBeside_ s sl rest
                               where
                                  rest = case p of
                                           Empty -> nilBeside g q
                                           _     -> beside p g q


nilBeside :: Bool -> RDoc -> RDoc
-- Specification: text "" <> nilBeside g p
--              = text "" <g> p

nilBeside _ Empty      = Empty  -- Hence the text "" in the spec
nilBeside g (Nest _ p) = nilBeside g p
nilBeside g p          | g         = textBeside_ space_text 1 p
                       | otherwise = p

-- ---------------------------------------------------------------------------
-- Separate, @sep@, Hughes version

-- Specification: sep ps  = oneLiner (hsep ps)
--                         `union`
--                          vcat ps

sep = sepX True         -- Separate with spaces
cat = sepX False        -- Don't

sepX :: Bool -> [Doc] -> Doc
sepX _ []     = empty
sepX x (p:ps) = sep1 x (reduceDoc p) 0 ps


-- Specification: sep1 g k ys = sep (x : map (nest k) ys)
--                            = oneLiner (x <g> nest k (hsep ys))
--                              `union` x $$ nest k (vcat ys)

sep1 :: Bool -> RDoc -> Int -> [Doc] -> RDoc
sep1 _ _                   k _ | k `seq` False = (error "Pretty.hs")
sep1 _ NoDoc               _ _  = NoDoc
sep1 g (p `Union` q)       k ys = sep1 g p k ys
                                  `union_`
                                  (aboveNest q False k (reduceDoc (vcat ys)))
sep1 g Empty               k ys = mkNest k (sepX g ys)
sep1 g (Nest n p)          k ys = nest_ n (sep1 g p (k - n) ys)
sep1 _ (NilAbove p) k s = nilAbove_ (aboveNest p False k (reduceDoc (vcat s)))
sep1 g (TextBeside s sl p) k ys = textBeside_ s sl (sepNB g p (k - sl) ys)
sep1 _ _ _ _ = error "Pretty.sep1"

-- Specification: sepNB p k ys = sep1 (text "" <> p) k ys
-- Called when we have already found some text in the first item
-- We have to eat up nests

sepNB :: Bool -> Doc -> Int -> [Doc] -> Doc
sepNB g (Nest _ p)  k ys  = sepNB g p k ys

sepNB g Empty k ys        = oneLiner (nilBeside g (reduceDoc rest))
                                `mkUnion`
                            nilAboveNest False k (reduceDoc (vcat ys))
                          where
                            rest | g         = hsep ys
                                 | otherwise = hcat ys

sepNB g p k ys            = sep1 g p k ys

-- ---------------------------------------------------------------------------
-- @fill@

fsep = fill True
fcat = fill False

-- Specification:
--   fill []  = empty
--   fill [p] = p
--   fill (p1:p2:ps) = oneLiner p1 <#> nest (length p1)
--                                          (fill (oneLiner p2 : ps))
--                     `union`
--                      p1 $$ fill ps

fill :: Bool -> [Doc] -> Doc
fill _ []     = empty
fill g (p:ps) = fill1 g (reduceDoc p) 0 ps


fill1 :: Bool -> RDoc -> Int -> [Doc] -> Doc
fill1 _ _                   k _ | k `seq` False = (error "Pretty.hs")
fill1 _ NoDoc               _ _  = NoDoc
fill1 g (p `Union` q)       k ys = fill1 g p k ys
                                   `union_`
                                   (aboveNest q False k (fill g ys))

fill1 g Empty               k ys = mkNest k (fill g ys)
fill1 g (Nest n p)          k ys = nest_ n (fill1 g p (k - n) ys)

fill1 g (NilAbove p)        k ys = nilAbove_ (aboveNest p False k (fill g ys))
fill1 g (TextBeside s sl p) k ys = textBeside_ s sl (fillNB g p (k - sl) ys)
fill1 _ _ _ _ = error "Pretty.fill1"

fillNB :: Bool -> Doc -> Int -> [Doc] -> Doc
fillNB _ _          k _ | k `seq` False = (error "Pretty.hs")
fillNB g (Nest _ p) k s = fillNB g p k s
fillNB _ Empty _ []     = Empty
fillNB g Empty k (y:ys) = nilBeside g (fill1 g (oneLiner (reduceDoc y)) k1 ys)
                             `mkUnion`
                             nilAboveNest False k (fill g (y:ys))
                           where
                             k1 | g         = k - 1
                                | otherwise = k

fillNB g p k ys            = fill1 g p k ys


-- ---------------------------------------------------------------------------
-- Selecting the best layout

best :: Mode
     -> Int             -- Line length
     -> Int             -- Ribbon length
     -> RDoc
     -> RDoc            -- No unions in here!

best OneLineMode _ _ p'
  = get p'
  where
    get Empty               = Empty
    get NoDoc               = NoDoc
    get (NilAbove p)        = nilAbove_ (get p)
    get (TextBeside s sl p) = textBeside_ s sl (get p)
    get (Nest _ p)          = get p             -- Elide nest
    get (p `Union` q)       = first (get p) (get q)
    get _                   = error "Pretty.best.get"

best _ w' r p'
  = get w' p'
  where
    get :: Int          -- (Remaining) width of line
        -> Doc -> Doc
    get w _ | w==0 && False   = (error "Pretty.hs")
    get _ Empty               = Empty
    get _ NoDoc               = NoDoc
    get w (NilAbove p)        = nilAbove_ (get w p)
    get w (TextBeside s sl p) = textBeside_ s sl (get1 w sl p)
    get w (Nest k p)          = nest_ k (get (w - k) p)
    get w (p `Union` q)       = nicest w r (get w p) (get w q)
    get _ _                   = error "Pretty.best.get2"

    get1 :: Int         -- (Remaining) width of line
         -> Int         -- Amount of first line already eaten up
         -> Doc         -- This is an argument to TextBeside => eat Nests
         -> Doc         -- No unions in here!

    get1 w _ _ | w==0 && False = (error "Pretty.hs")
    get1 _ _  Empty               = Empty
    get1 _ _  NoDoc               = NoDoc
    get1 w sl (NilAbove p)        = nilAbove_ (get (w - sl) p)
    get1 w sl (TextBeside t tl p) = textBeside_ t tl (get1 w (sl + tl) p)
    get1 w sl (Nest _ p)          = get1 w sl p
    get1 w sl (p `Union` q)       = nicest1 w r sl (get1 w sl p)
                                                   (get1 w sl q)
    get1 _ _ _                    = error "Pretty.best.get1"

nicest :: Int -> Int -> Doc -> Doc -> Doc
nicest w r p q = nicest1 w r 0 p q
nicest1 :: Int -> Int -> Int -> Doc -> Doc -> Doc
nicest1 w r sl p q | fits ((w `minn` r) - sl) p = p
                   | otherwise                  = q
                     where minn x y | x < y     = x
                                    | otherwise = y

fits :: Int     -- Space available
     -> Doc
     -> Bool    -- True if *first line* of Doc fits in space available

fits n _    | n < 0 = False
fits _ NoDoc               = False
fits _ Empty               = True
fits _ (NilAbove _)        = True
fits n (TextBeside _ sl p) = fits (n - sl) p
fits _ _                   = error "Pretty.fits"

-- @first@ and @nonEmptySet@ are similar to @nicest@ and @fits@, only simpler.
-- @first@ returns its first argument if it is non-empty, otherwise its second.

first :: Doc -> Doc -> Doc
first p q | nonEmptySet p = p
          | otherwise     = q

nonEmptySet :: Doc -> Bool
nonEmptySet NoDoc              = False
nonEmptySet (_ `Union` _)      = True
nonEmptySet Empty              = True
nonEmptySet (NilAbove _)       = True           -- NoDoc always in first line
nonEmptySet (TextBeside _ _ p) = nonEmptySet p
nonEmptySet (Nest _ p)         = nonEmptySet p
nonEmptySet _                  = error "Pretty.nonEmptySet"

-- @oneLiner@ returns the one-line members of the given set of @Doc@s.

oneLiner :: Doc -> Doc
oneLiner NoDoc               = NoDoc
oneLiner Empty               = Empty
oneLiner (NilAbove _)        = NoDoc
oneLiner (TextBeside s sl p) = textBeside_ s sl (oneLiner p)
oneLiner (Nest k p)          = nest_ k (oneLiner p)
oneLiner (p `Union` _)       = oneLiner p
oneLiner _                   = error "Pretty.oneLiner"

-- ---------------------------------------------------------------------------
-- Displaying the best layout

renderStyle = renderStyle' ""

renderStyle' :: String -> Style -> Doc -> String
renderStyle' rest style' doc
  = fullRender (mode style')
               (lineLength style')
               (ribbonsPerLine style')
               string_txt
               rest
               doc

render doc       = showDoc doc ""
showDoc :: Doc -> String -> String
showDoc doc rest = renderStyle' rest style doc

string_txt :: TextDetails -> String -> String
string_txt (Chr c)   s  = c:s
string_txt (Str s1)  s2 = s1 ++ s2
string_txt (PStr s1) s2 = s1 ++ s2


fullRender OneLineMode _ _ txt end doc =
    easy_display space_text txt end (reduceDoc doc)
fullRender LeftMode    _ _ txt end doc =
    easy_display nl_text    txt end (reduceDoc doc)

fullRender mode' line_length ribbons_per_line txt end doc
  = display mode' line_length ribbon_length txt end best_doc
  where
    best_doc = best mode' hacked_line_length ribbon_length (reduceDoc doc)

    hacked_line_length, ribbon_length :: Int
    ribbon_length = round (fromIntegral line_length / ribbons_per_line)
    hacked_line_length = case mode' of
                         ZigZagMode -> maxBound
                         _ -> line_length

display :: Mode -> Int -> Int -> (TextDetails -> a -> a) -> a -> Doc -> a
display mode' page_width ribbon_width txt end doc
  = case page_width - ribbon_width of { gap_width ->
    case gap_width `quot` 2 of { shift ->
    let
        lay k _            | k `seq` False = (error "Pretty.hs")
        lay k (Nest k1 p)  = lay (k + k1) p
        lay _ Empty        = end

        lay k (NilAbove p) = nl_text `txt` lay k p

        lay k (TextBeside s sl p)
            = case mode' of
                    ZigZagMode |  k >= gap_width
                               -> nl_text `txt` (
                                  Str (multi_ch shift '/') `txt` (
                                  nl_text `txt` (
                                  lay1 (k - shift) s sl p)))

                               |  k < 0
                               -> nl_text `txt` (
                                  Str (multi_ch shift '\\') `txt` (
                                  nl_text `txt` (
                                  lay1 (k + shift) s sl p )))

                    _ -> lay1 k s sl p
        lay _ _ = error "Pretty.lay"

        lay1 k _ sl _ | k+sl `seq` False = (error "Pretty.hs")
        lay1 k s sl p = Str (indent k) `txt` (s `txt` lay2 (k + sl) p)

        lay2 k _ | k `seq` False = (error "Pretty.hs")
        lay2 k (NilAbove p)        = nl_text `txt` lay k p
        lay2 k (TextBeside s sl p) = s `txt` (lay2 (k + sl) p)
        lay2 k (Nest _ p)          = lay2 k p
        lay2 _ Empty               = end
        lay2 _ _                   = error "Pretty.lay2"
    in
    lay 0 doc
    }}

easy_display :: TextDetails -> (TextDetails -> a -> a) -> a -> Doc -> a
easy_display nl txt end doc
  = lay doc cant_fail
  where
    cant_fail = error "easy_display: NoDoc"
    lay NoDoc               no_doc = no_doc
    lay (Union _p q)       _no_doc = {- lay p -} (lay q cant_fail)
    -- Second arg can't be NoDoc
    lay (Nest _ p)          no_doc = lay p no_doc
    lay Empty              _no_doc = end
    lay (NilAbove p)       _no_doc = nl `txt` lay p cant_fail
    -- NoDoc always on first line
    lay (TextBeside s _ p)  no_doc = s `txt` lay p no_doc
    lay _                   _      = error "Pretty.easy_display.lay"

indent :: Int -> String
indent n = multi_ch n ' '

multi_ch :: Int -> Char -> String
multi_ch = replicate
