{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

parser for HasCASL kinds, types, terms, patterns and equations
-}

module HasCASL.ParseTerm where

import Common.AnnoState
import Common.Id
import Common.Keywords
import Common.Lexer
import Common.Token
import HasCASL.HToken
import HasCASL.As
import Text.ParserCombinators.Parsec
import Data.List

-- * key sign tokens

-- | keywords for the variance of kinds  
plusT, minusT :: AParser st Token
plusT = asKey plusS
minusT = asKey minusS

-- | a colon not followed by a question mark
colT :: AParser st Token
colT = asKey colonS

-- | a colon immediately followed by a question mark
qColonT :: AParser st Token
qColonT = asKey (colonS++quMark)

-- * parser for bracketed lists

-- | a generic bracket parser 
bracketParser :: AParser st a -> AParser st Token -> AParser st Token 
              -> AParser st Token -> ([a] -> [Pos] -> b) -> AParser st b
bracketParser parser op cl sep k = 
    do o <- op
       (ts, ps) <- option ([], []) (parser `separatedBy` sep)
       c <- cl
       return (k ts (toPos o ps c))

-- | parser for square brackets
mkBrackets :: AParser st a -> ([a] -> [Pos] -> b) -> AParser st b
mkBrackets p c = bracketParser p oBracketT cBracketT anComma c

-- | parser for braces
mkBraces :: AParser st a -> ([a] -> [Pos] -> b) -> AParser st b
mkBraces p c = bracketParser p oBraceT cBraceT anComma c

-- * kinds

-- | parse a simple class name or the type universe as kind
parseClassId :: AParser st Kind
parseClassId = fmap (\c -> if showId c "" == "Type" 
                   then Intersection [] $ posOfId c
                   else ClassKind c MissingKind) classId

-- | do 'parseClassId' or a downset or an intersection kind 
parseSimpleKind :: AParser st Kind
parseSimpleKind = parseClassId
             <|> 
             do o <- oParenT
                (cs, ps) <- kind `separatedBy` anComma
                c <- cParenT
                return (if isSingle cs then head cs else
                        Intersection cs (toPos o ps c))
             <|>
             do o <- oBraceT
                i <- pToken scanHCWords
                d <- dotT
                j <- asKey (tokStr i)
                l <- lessT
                t <- parseType
                p <- cBraceT
                return (Downset (Just i) t MissingKind 
                        (catPos [o,d,j,l,p])) 

-- | do 'parseSimpleKind' and check for an optional 'Variance'
parseExtKind :: AParser st Kind
parseExtKind = do 
    v <- option (mkSimpleId "") (plusT <|> minusT)
    k <- parseSimpleKind
    let s = tokStr v
        p = tokPos v
    return $ if s == plusS then ExtKind k CoVar p
           else if s == minusS then ExtKind k ContraVar p else k

-- | parse a (right associative) function kind for a given argument kind
arrowKind :: Kind -> AParser st Kind
arrowKind k1 =
       do a <- asKey funS
          k2 <- kind
          return (FunKind k1 k2 $ tokPos a)

-- | parse a function kind but reject an extended kind
kind :: AParser st Kind
kind = 
    do k1 <- parseExtKind
       arrowKind k1 <|> case k1 of
            ExtKind _ _ _ -> unexpected "variance of kind"
            _ -> return k1

-- | parse a function kind but accept an extended kind
extKind :: AParser st Kind
extKind = 
    do k1 <- parseExtKind
       arrowKind k1 <|> return k1


-- * type variables

-- a (simple) type variable with a 'Variance'
extVar :: AParser st Id -> AParser st (Id, Maybe Variance, [Pos]) 
extVar vp = 
    do t <- vp
       do   a <- plusT
            return (t, Just CoVar, tokPos a)
          <|>
          do a <- minusT
             return (t, Just ContraVar, tokPos a)
          <|> return (t, Nothing, [])

-- several 'extVar' with a 'Kind'
typeVars :: AParser st [TypeArg]
typeVars = do (ts, ps) <- extVar typeVar `separatedBy` anComma
              typeKind ts ps

allIsInVar :: [(TypeId, Maybe Variance, [Pos])] -> Bool
allIsInVar = all ( \ (_, v, _) -> maybe True (const False) v)


-- 'parseType' a 'Downset' starting with 'lessT'
typeKind :: [(TypeId, Maybe Variance, [Pos])] -> [Token] 
         -> AParser st [TypeArg]
typeKind vs ps = 
    do c <- colT
       if allIsInVar vs then 
          do k <- extKind
             return (makeTypeArgs vs ps (tokPos c) k)
          else do k <- kind
                  return (makeTypeArgs vs ps (tokPos c) k)
    <|>
    do l <- lessT
       t <- parseType
       return (makeTypeArgs vs ps (tokPos l)
                  (Downset Nothing t MissingKind [])) 
    <|> return (makeTypeArgs vs ps [] star)

-- | add the 'Kind' to all 'extVar' and yield a 'TypeArg'
makeTypeArgs :: [(TypeId, Maybe Variance, [Pos])] -> [Token] 
             -> [Pos] -> Kind -> [TypeArg]
makeTypeArgs ts ps qs k = 
    zipWith (mergeVariance Comma k) (init ts) 
                (map tokPos ps)
                ++ [mergeVariance Other k (last ts) qs]
                where mergeVariance c e (t, Nothing, _) q =
                          TypeArg t e c q
                      mergeVariance c e (t, Just v, p) q = 
                          TypeArg t (ExtKind e v p) c q 

-- | a single 'TypeArg' (parsed by 'typeVars')
singleTypeArg :: AParser st TypeArg
singleTypeArg = do  as <- typeVars
                    case as of 
                            [a] -> return a 
                            _ -> unexpected "list of type arguments"

-- | a 'singleTypeArg' put in parentheses
parenTypeArg :: AParser st (TypeArg, [Token])
parenTypeArg = 
    do o <- oParenT
       a <- singleTypeArg
       p <- cParenT
       return (a, [o, p])

-- | a 'singleTypeArg' possibly put in parentheses
typeArg :: AParser st (TypeArg, [Token])
typeArg = 
    do a <- singleTypeArg
       return (a, [])
     <|> parenTypeArg

-- | several 'typeArg's 
typeArgs :: AParser st ([TypeArg], [Token])
typeArgs = 
    do l <- many1 typeArg
       return (map fst l, concatMap snd l)

-- | a 'singleTypeArg' put in parentheses as 'TypePattern'
typePatternArg :: AParser st TypePattern
typePatternArg = 
    do (a, ps) <- parenTypeArg
       return $ TypePatternArg a $ catPos ps

-- * parse special identifier tokens

type TokenMode = [String]   

-- | parse a 'Token' of an 'Id' (to be declared) 
-- but exclude the signs in 'TokenMode'
aToken :: TokenMode -> AParser st Token
aToken b = pToken (scanQuotedChar <|> scanDigit <|> scanHCWords <|> placeS <|> 
                   reserved b scanHCSigns)

-- | just 'aToken' only excluding basic HasCASL keywords
idToken :: AParser st Token
idToken = aToken [] <|> pToken scanDotWords 

-- * type patterns

-- 'TypePatternToken's within 'BracketTypePattern's 
-- may recusively be 'idToken's.
-- Parenthesis are only legal for a 'typePatternArg'.
primTypePatternOrId :: AParser st TypePattern
primTypePatternOrId = fmap TypePatternToken idToken 
               <|> mkBraces typePatternOrId (BracketTypePattern Braces)
               <|> mkBrackets typePatternOrId (BracketTypePattern Squares)
               <|> typePatternArg

-- several 'primTypePatternOrId's possibly yielding a 'MixfixTypePattern'
typePatternOrId :: AParser st TypePattern
typePatternOrId = do ts <- many1 primTypePatternOrId
                     return( if isSingle ts then head ts
                             else MixfixTypePattern ts)

-- | those (top-level) 'Token's (less than 'idToken') 
-- that may appear in 'TypePattern's as 'TypePatternToken'.
typePatternToken :: AParser st TypePattern
typePatternToken = fmap TypePatternToken (pToken (scanHCWords <|> placeS <|> 
                          reserved [assignS, lessS, equalS] scanHCSigns))

-- | a 'typePatternToken' or something in braces (a 'typePattern'),
-- in square brackets (a 'typePatternOrId' covering compound lists) 
-- or parenthesis ('typePatternArg')
primTypePattern :: AParser st TypePattern
primTypePattern = typePatternToken 
           <|> mkBrackets typePatternOrId (BracketTypePattern Squares)
           <|> mkBraces typePattern (BracketTypePattern Braces)
           <|> typePatternArg

-- several 'primTypePatter's possibly yielding a 'MixfixTypePattern'
typePattern :: AParser st TypePattern
typePattern = do ts <- many1 primTypePattern
                 let t = if isSingle ts then head ts 
                         else MixfixTypePattern ts
                   in return t

-- * types 
-- a parsed type may also be interpreted as a kind (by the mixfix analysis)

-- | type tokens with some symbols removed
typeToken :: AParser st Type
typeToken = fmap TypeToken (pToken (scanHCWords <|> placeS <|> 
                                    reserved (assignS : lessS : equalS : barS :
                                              hascasl_type_ops) 
                                    scanHCSigns))


-- | 'TypeToken's within 'BracketType's may recusively be
-- 'idToken's. Parenthesis may group a mixfix type 
-- or may be interpreted as 'Intersection' later in a GEN-VAR-DECL.
primTypeOrId :: AParser st Type
primTypeOrId = fmap TypeToken idToken
               <|> mkBrackets typeOrId (BracketType Squares)
               <|> mkBraces typeOrId (BracketType Braces)
               <|> bracketParser typeOrId oParenT cParenT anComma
                       (BracketType Parens)
               
-- | several 'primTypeOrId's possibly yielding a 'MixfixType' 
-- and possibly followed by a 'kindAnno'.
typeOrId :: AParser st Type
typeOrId = do ts <- many1 primTypeOrId
              let t = if isSingle ts then head ts
                      else MixfixType ts
                 in 
                 kindAnno t
                 <|> 
                 return(t)

-- | a 'Kind' annotation starting with 'colT'.
kindAnno :: Type -> AParser st Type
kindAnno t = do c <- colT 
                k <- kind
                return (KindedType t k $ tokPos c)

-- | a typeToken' or a 'BracketType'. Square brackets may contain 'typeOrId'.
primType :: AParser st Type
primType = typeToken 
           <|> mkBrackets typeOrId (BracketType Squares)
           <|> mkBraces parseType (BracketType Braces)
           <|> bracketParser parseType oParenT cParenT anComma 
                   (BracketType Parens)

-- | a 'primType' possibly preceded by 'quMarkT'
lazyType :: AParser st Type
lazyType = do q <- quMarkT
              t <- primType 
              return (LazyType t $ tokPos q)
           <|> primType

-- | several 'lazyType's (as 'MixfixType') possibly followed by 'kindAnno' 
mixType :: AParser st Type
mixType = do ts <- many1 lazyType
             let t = if isSingle ts then head ts else MixfixType ts
               in kindAnno t
                  <|> return t 

-- | 'mixType' possibly interspersed with 'crossT' 
prodType :: AParser st Type
prodType = do (ts, ps) <- mixType `separatedBy` crossT
              return $ mkProductType ts $ catPos ps

-- | a (right associativ) function type  
parseType :: AParser st Type
parseType = 
    do t1 <- prodType 
       do a <- arrowT <?> funS
          t2 <- parseType
          return (FunType t1 (fst a) t2 $ snd a)
        <|> return t1

-- | parse one of the four possible 'Arrow's
arrowT :: AParser st (Arrow, [Pos])
arrowT = do a <- asKey funS
            return (FunArr, tokPos a)
         <|>
         do a <- asKey pFun
            return (PFunArr, tokPos a)
         <|>
         do a <- asKey contFun
            return (ContFunArr, tokPos a)
         <|>
         do a <- asKey pContFun 
            return (PContFunArr, tokPos a)

-- | parse a 'TypeScheme' using 'forallT', 'typeVars', 'dotT' and 'parseType'
typeScheme :: AParser st TypeScheme
typeScheme = do f <- forallT
                (ts, cs) <- typeVars `separatedBy` anSemi
                d <- dotT
                t <- typeScheme
                return $ case t of 
                         TypeScheme ots q ps ->
                             TypeScheme (concat ts ++ ots) q 
                                        (toPos f cs d ++ ps)
             <|> fmap simpleTypeScheme parseType


data TypeOrTypeScheme = PartialType Type | TotalTypeScheme TypeScheme

-- a 'TypeOrTypescheme' for a possibly partial constant (given by 'qColonT')
typeOrTypeScheme :: AParser st (Token, TypeOrTypeScheme)
typeOrTypeScheme = do q <- qColonT
                      t <- parseType 
                      return (q, PartialType t)
                   <|>
                   do q <- colT 
                      s <- typeScheme
                      return (q, TotalTypeScheme s)

toPartialTypeScheme :: [Pos] -> TypeOrTypeScheme -> TypeScheme
toPartialTypeScheme qs ts = case ts of 
            PartialType t -> simpleTypeScheme $ liftType t qs
            TotalTypeScheme s -> s

partialTypeScheme :: AParser st (Token, TypeScheme)
partialTypeScheme = do (c, ts) <- typeOrTypeScheme
                       return (c, toPartialTypeScheme (tokPos c) ts)


-- * varDecls and genVarDecls

-- | comma separated 'var' with 'varDeclType'
varDecls :: AParser st [VarDecl]
varDecls = do (vs, ps) <- var `separatedBy` anComma
              varDeclType vs ps

-- | a type ('parseType') following a 'colT' 
varDeclType :: [Var] -> [Token] -> AParser st [VarDecl]
varDeclType vs ps = do c <- colT
                       t <- parseType
                       return (makeVarDecls vs ps t (tokPos c))

-- | attach the 'Type' to every 'Var'
makeVarDecls :: [Var] -> [Token] -> Type -> [Pos] -> [VarDecl]
makeVarDecls vs ps t q = zipWith (\ v p -> VarDecl v t Comma $ tokPos p)
                     (init vs) ps ++ [VarDecl (last vs) t Other q]

-- | either like 'varDecls' or declared type variables.
-- A 'GenVarDecl' may later become a 'GenTypeVarDecl'.
genVarDecls:: AParser st [GenVarDecl]
genVarDecls = do (vs, ps) <- extVar var `separatedBy` anComma
                 if allIsInVar vs then
                    fmap (map GenVarDecl) 
                             (varDeclType 
                              (map ( \ (i, _, _) -> i) vs) ps)
                      <|> fmap (map GenTypeVarDecl)
                               (typeKind vs ps)
                     else fmap (map GenTypeVarDecl)
                               (typeKind vs ps)

-- * patterns

{- | different legal 'TermToken's possibly excluding 'funS' or
'equalS' for case or let patterns resp. -}
tokenPattern :: TokenMode -> AParser st Pattern
tokenPattern b = fmap TermToken (aToken b <|> pToken (string "_"))
-- a single underscore serves as wildcard pattern
                                          
-- | 'tokenPattern' or 'BracketTerm'
primPattern :: TokenMode -> AParser st Pattern
primPattern b = tokenPattern b 
                <|> mkBrackets pattern (BracketTerm Squares)
                <|> mkBraces pattern (BracketTerm Braces) 
                <|> bracketParser pattern oParenT cParenT anComma
                        (BracketTerm Parens)

-- | several 'typedPattern'
mixPattern :: TokenMode -> AParser st Pattern
mixPattern b = 
    do l <- many1 $ asPattern b
       return $ if isSingle l then head l else MixfixTerm l

-- | a possibly typed ('parseType') pattern
typedPattern :: TokenMode -> AParser st Pattern
typedPattern b = 
    do t <- primPattern b
       do c <- colT
          ty <- parseType
          return (MixfixTerm [t, MixTypeTerm OfType ty $ tokPos c])
        <|> return t

-- | top-level pattern (possibly 'AsPattern')
asPattern :: TokenMode -> AParser st Pattern
asPattern b = 
    do v <- typedPattern b
       case v of 
           TermToken tt -> if isPlace tt then return v else do 
               c <- asKey asP 
               t <- typedPattern b 
               return (AsPattern 
                       (VarDecl (mkId [tt]) (MixfixType []) Other $ tokPos c)
                       t $ tokPos c)
             <|> return v 
           _ -> return v

-- | an unrestricted 'asPattern'
pattern :: AParser st Pattern
pattern = mixPattern []

-- | a 'Total' or 'Partial' lambda dot
lamDot :: AParser st (Partiality, Token)
lamDot = do d <- asKey (dotS++exMark) <|> asKey (cDot++exMark)
            return (Total,d)
         <|> 
         do d <- dotT
            return (Partial,d)

-- | patterns between 'lamS' and 'lamDot'
lamPattern :: AParser st [Pattern]
lamPattern = 
    do  lookAhead lamDot 
        return []
      <|> do p <- pattern
             ps <- lamPattern
             return (p : ps)

-- * terms

-- | an 'uninstOpId' possibly followed by types ('parseType') in brackets 
-- and further places ('placeT')
instOpId :: AParser st InstOpId
instOpId = do i <- uninstOpId
              (ts, qs) <- option ([], [])
                                       (mkBrackets parseType (,))
              return (InstOpId i ts qs)

{- | 'Token's that may occur in 'Term's including literals
   'scanFloat', 'scanString' but excluding 'ifS', 'whenS' and 'elseS'
   to allow a quantifier after 'whenS'. In case terms also 'barS' will
   excluded on the top-levek. -}

tToken :: TokenMode -> AParser st Token
tToken b = pToken(scanFloat <|> scanString 
                <|> scanQuotedChar <|> scanDotWords 
                <|> reserved [ifS, whenS, elseS] scanHCWords 
                <|> reserved b scanHCSigns 
                <|> placeS <?> "id/literal" )


-- | 'tToken' as 'Term' plus 'exEqual' and 'equalS'
termToken :: TokenMode -> AParser st Term
termToken b = fmap TermToken (asKey exEqual <|> asKey equalS <|> tToken b)

-- | 'termToken' plus 'BracketTerm's
primTerm :: TokenMode -> AParser st Term
primTerm b = termToken b
           <|> mkBraces termInParens (BracketTerm Braces)
           <|> mkBrackets termInParens (BracketTerm Squares)
           <|> bracketParser termInParens oParenT cParenT anComma
                       (BracketTerm Parens)

-- | how the keyword 'inS' should be treated  
data InMode = NoIn   -- ^ next 'inS' belongs to 'letS' 
            | WithIn -- ^ 'inS' is the element test 

-- | all 'Term's that start with a unique keyword
baseTerm :: (InMode, TokenMode) -> AParser st Term
baseTerm b = ifTerm b
           <|> whenTerm b   
           <|> forallTerm b 
           <|> exTerm b 
           <|> lambdaTerm b 
           <|> caseTerm b
           <|> letTerm b

-- | 'whenS' possibly followed by an 'elseS'
whenTerm :: (InMode, TokenMode) -> AParser st Term
whenTerm b = 
    do i <- asKey whenS
       c <- mixTerm b
       do t <- asKey elseS
          e <- mixTerm b
          return (MixfixTerm [TermToken i, c, TermToken t, e])
        <|> return (MixfixTerm [TermToken i, c])

-- | 'ifS' possibly followed by 'thenS' and 'elseS'
-- yielding a 'MixfixTerm'
ifTerm :: (InMode, TokenMode) -> AParser st Term
ifTerm b = 
    do i <- asKey ifS
       c <- mixTerm b
       do t <- asKey thenS
          e <- mixTerm b
          do s <- asKey elseS 
             f <- mixTerm b
             return (MixfixTerm [TermToken i, c, TermToken t, e, 
                                 TermToken s, f])
           <|> return (MixfixTerm [TermToken i, c, TermToken t, e]) 
        <|> return (MixfixTerm [TermToken i, c])

-- | unrestricted terms including qualified names 
termInParens :: AParser st Term
termInParens = term <|> varTerm <|> qualOpName <|> qualPredName

-- | a qualified 'var'
varTerm :: AParser st Term
varTerm = 
    do v <- asKey varS
       i <- var
       c <- colT
       t <- parseType
       return $ QualVar $ VarDecl i t Other $ toPos v [] c

-- | 'opS' or 'functS'
opBrand :: AParser st (Token, OpBrand)
opBrand = bind (,) (asKey opS) (return Op)
          <|> bind (,) (asKey functS) (return Fun) 

-- | a qualified operation (with 'opBrand') 
qualOpName :: AParser st Term
qualOpName = 
    do (v, b) <- opBrand
       i <- instOpId
       (c, t) <- partialTypeScheme
       return $ QualOp b i t $ toPos v [] c

-- | a qualified predicate
qualPredName :: AParser st Term
qualPredName = 
    do v <- asKey predS
       i <- instOpId
       c <- colT 
       t <- typeScheme
       return $ QualOp Pred i (predTypeScheme t) $ toPos v [] c


-- | a qualifier expecting a further 'Type'. 
-- 'inS' is rejected for 'NoIn'
typeQual :: InMode -> AParser st (TypeQual, Token) 
typeQual m = 
              do q <- colT
                 return (OfType, q)
              <|> 
              do q <- asT
                 return (AsType, q)
              <|> 
              case m of 
                     NoIn -> pzero
                     WithIn -> 
                         do q <- asKey inS
                            return (InType, q)

-- | a possibly type qualified ('typeQual') 'primTerm' or a 'baseTerm' 
typedTerm :: (InMode, TokenMode) -> AParser st Term
typedTerm (i, b) = 
    do t <- primTerm b
       do (q, p) <- typeQual i
          ty <- parseType
          return (MixfixTerm [t, MixTypeTerm q ty $ tokPos p])
        <|> return t
      <|> baseTerm (i, b)

-- | several 'typedTerm's yielding a 'MixfixTerm'
mixTerm :: (InMode, TokenMode) -> AParser st Term
mixTerm b = 
    do ts <- many1 $ typedTerm b
       return $ if isSingle ts then head ts else MixfixTerm ts

-- | keywords that start a new item 
hasCaslStartKeywords :: [String]
hasCaslStartKeywords = 
    dotS:cDot: (hascasl_reserved_words \\ [existsS, letS, caseS])

-- | a 'mixTerm' followed by 'whereS' and equations separated by 'optSemi'
whereTerm :: (InMode, TokenMode) -> AParser st Term
whereTerm b = 
    do t <- mixTerm b 
       do p <- asKey whereS
          (es, ps, _ans) <- itemAux hasCaslStartKeywords $
                           patternTermPair ([equalS]) b equalS 
          -- ignore collected annotations
          return (LetTerm Where es t $ catPos $ p:ps)
        <|> return t

-- | a 'whereTerm' called with ('WithIn', [])
term :: AParser st Term
term = whereTerm (WithIn, [])

-- | a 'Universal' 'QuantifiedTerm'
forallTerm :: (InMode, TokenMode) -> AParser st Term
forallTerm b = 
    do f <- forallT
       (vs, ps) <- genVarDecls `separatedBy` anSemi
       addAnnos
       d <- dotT
       t <- mixTerm b
       return $ QuantifiedTerm Universal (concat vs) t $ toPos f ps d

-- | 'Unique' or 'Existential'
exQuant :: AParser st (Token, Quantifier)
exQuant =
    bind (,) (asKey (existsS++exMark)) (return Unique)
             <|> bind (,) (asKey existsS) (return Existential)

-- | a (possibly unique) existential 'QuantifiedTerm'
exTerm :: (InMode, TokenMode) -> AParser st Term
exTerm b = 
    do (p, q) <- exQuant <?> existsS
       (vs, ps) <- varDecls `separatedBy` anSemi
       d <- dotT
       f <- mixTerm b
       return $ QuantifiedTerm q (map GenVarDecl (concat vs)) f $ toPos p ps d

-- | a 'LambdaTerm'
lambdaTerm :: (InMode, TokenMode) -> AParser st Term
lambdaTerm b = 
             do l <- asKey lamS
                pl <- lamPattern
                (k, d) <- lamDot      
                t <- mixTerm b
                return (LambdaTerm pl k t (toPos l [] d))

-- | a 'CaseTerm' with 'funS' excluded in 'patternTermPair'
caseTerm :: (InMode, TokenMode) -> AParser st Term
caseTerm (i, _) = 
           do c <- asKey caseS
              t <- term
              o <- asKey ofS
              (ts, ps) <- patternTermPair [funS] (i, [barS]) funS 
                          `separatedBy` barT
              return (CaseTerm t ts $ catPos $ c:o:ps)

-- | a 'LetTerm' with 'equalS' excluded in 'patternTermPair' 
-- (called with 'NoIn')
letTerm :: (InMode, TokenMode) -> AParser st Term
letTerm b = 
          do l <- asKey letS
             (es, ps) <- patternTermPair [equalS] (NoIn, []) equalS 
                         `separatedBy` anSemi 
             i <- asKey inS
             t <- mixTerm b
             return (LetTerm Let es t (toPos l ps i))

-- | a customizable pattern equation 
patternTermPair :: TokenMode -> (InMode, TokenMode) -> String 
                -> AParser st ProgEq
patternTermPair b1 b2 sep = 
    do p <- mixPattern b1
       s <- asKey sep
       t <- mixTerm b2
       return (ProgEq p t $ tokPos s)
