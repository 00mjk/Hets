module AS_Basic_CASL where

import Id
import AS_Annotation 

data BASIC_SPEC = Basic_spec [Annoted BASIC_ITEMS]
		  deriving (Show,Eq)

data BASIC_ITEMS = Sig_items SIG_ITEMS 
                   -- the Annotation following the keyword is dropped
		   -- but preceding the keyword is now an Annotation allowed
		 | Free_datatype [DATATYPE_DECL] [Pos]
		   -- pos: free, type, semi colons
		 | Sort_gen [Annoted SIG_ITEMS] [Pos] 
		   -- pos: generated, opt. braces (type in Datatype_items)
		 | Var_items [VAR_DECL] [Pos]
		   -- pos: var, semi colons
		 | Local_var_axioms [VAR_DECL] [Annoted FORMULA] [Pos]
		   -- pos: forall, dots
		 | Axiom_items [Annoted FORMULA] [Pos]
		   -- pos: dots
		   deriving (Show,Eq)

data SIG_ITEMS = Sort_items [Annoted SORT_ITEM] [Pos] 
	         -- pos: sort, semi colons
	       | Op_items [Annoted OP_ITEM] [Pos]
		 -- pos: op, semi colons
	       | Pred_items [Annoted PRED_ITEM] [Pos]
		 -- pos: pred, semi colons
	       | Datatype_items [DATATYPE_DECL]
		 -- type, semi colons
		 deriving (Show,Eq)

data SORT_ITEM = Sort_decl [SORT] [Pos]
	         -- pos: commas
	       | Subsort_decl [SORT] SORT [Pos]
		 -- pos: commas, <
	       | Subsort_defn SORT VAR SORT (Annoted FORMULA) [Pos]
		 -- pos: "=", "{", ":", ".", "}"
	       | Iso_decl [SORT] [Pos]
	         -- pos: "="s
		 deriving (Show,Eq)

data OP_ITEM = Op_decl [OP_NAME] OP_TYPE [OP_ATTR] [Pos]
	       -- pos: commas, colon, OP_ATTR sep. by commas
	     | Op_defn OP_NAME OP_HEAD TERM [Pos]
	       -- pos: "="
	       deriving (Show,Eq)

data OP_TYPE = Total_op_type [SORT] SORT [Pos]
	       -- pos: "*"s, "->" ; if null [SORT] then [Pos] = [] 
	     | Partial_op_type [SORT] SORT [Pos]
	       -- pos: "*"s, "->?"; if null [SORT] then pos: "?"
	       deriving (Show,Eq)

data OP_HEAD = Total_op_head [ARG_DECL] SORT [Pos]
	       -- pos: "(", semicolons, ")", colon
	     | Partial_op_head [ARG_DECL] SORT [Pos]
	       deriving (Show,Eq)

data ARG_DECL = Arg_decl [VAR] SORT [Pos]
	        -- pos: commas, colon
		deriving (Show,Eq)

data OP_ATTR = Assoc_op_attr | Common_op_attr | Idem_op_attr
	     | Unit_op_attr TERM
	       deriving (Show,Eq)

data PRED_ITEM = Pred_decl [PRED_NAME] PRED_TYPE [Pos]
                 -- pos: commas, colon
	       | Pred_defn PRED_NAME PRED_HEAD (Annoted FORMULA) [Pos]
		 -- pos: "<=>"
		 deriving (Show,Eq)

data PRED_TYPE = Pred_type [SORT] [Pos]
	         -- pos: if null [SORT] then "(",")" else "*"s
		 deriving (Show,Eq)

data PRED_HEAD = Pred_head [ARG_DECL] [Pos]
	         -- pos: "(",semi colons , ")"
		 deriving (Show,Eq)

data DATATYPE_DECL = Datatype_decl SORT [Annoted ALTERNATIVE] [Pos] 
		     -- pos: "::=", "|"s
		     deriving (Show,Eq)

data ALTERNATIVE = Total_construct OP_NAME [COMPONENTS] [Pos]
		   -- pos: "(", semi colons, ")"
		 | Partial_construct OP_NAME [COMPONENTS] [Pos]
		   -- pos: "(", semi colons, ")", "?"
		 | Subsorts [SORT] [Pos]
		   -- pos: sort, commas
		   deriving (Show,Eq)

data COMPONENTS = Total_select [OP_NAME] SORT [Pos]
                  -- pos: commas, colon
		| Patial_select [OP_NAME] SORT [Pos] 
		  -- pos: commas, ":?"
		| Sort SORT		  
		  deriving (Show,Eq)

data VAR_DECL = Var_decl [VAR] SORT [Pos]
	        -- pos: commas, colon
		deriving (Show,Eq)

{- Position definition for FORMULA: 
   Information on parens are also encoded in [Pos].  If there
   are more Pos than necessary there is a pair of Pos enclosing the
   other Pos informations which encode the brackets of every kind
-}

data FORMULA = Quantfication QUANTIFIER [VAR_DECL] FORMULA [Pos]
	       -- pos: QUANTIFIER, semi colons, dot
	     | Conjunction [FORMULA] [Pos]
	       -- pos: "/\"s
	     | Disjunction [FORMULA] [Pos]
	       -- pos: "\/"s
	     | Implication FORMULA FORMULA [Pos]
	       -- pos: "=>" or "if" 	   
	     | Equivalence FORMULA FORMULA [Pos]
	       -- pos: "<=>"
	     | Negation FORMULA [Pos]
	       -- pos: not
	     | True_atom [Pos]
	       -- pos: true	    
	     | False_atom [Pos]
               -- pos: false
	     | Predication PRED_SYMB [TERM] [Pos]
               -- pos: opt. "(",commas,")"
	     | Definednes TERM [Pos]
	       -- pos: def
	     | Existl_equation TERM TERM [Pos]
               -- pos: =e=
	     | Strong_equation TERM TERM [Pos]
	       -- pos: =
	     | Membership TERM SORT [Pos]
               -- pos: in

	     -- a formula left original for mixfix analysis
	     | Unparsed_formula String [Pos]
	       -- pos: first Char in String
	       deriving (Show,Eq)

data QUANTIFIER = Universal | Existential | Unique_existential
		  deriving (Show,Eq)

data PRED_SYMB = Pred_name PRED_NAME 
	       | Qual_pred_name PRED_NAME PRED_TYPE [Pos]
		 -- pos: "(", pred, colon, ")"
		 deriving (Show,Eq)

{- Position and kind of brackets is provided by the list of Tokens -}

data TERM = Simple_id SIMPLE_ID [Token]-- "Var" might be a better constructor
	  | Qual_var VAR SORT [Pos] [Token]
	    -- pos: "(", var, colon, ")"
	  | Application OP_SYMB [TERM] [Pos] [Token]
	    -- pos: parens around [TERM] if any and seperating commas
	  | Sorted_term TERM SORT [Pos] [Token]
	    -- pos: colon
	  | Cast TERM SORT [Pos] [Token]
	    -- pos: 
	  | Conditional TERM FORMULA TERM [Pos] [Token]

	  | Unparsed_term String [Pos]

	  -- A new intermediate state
          | Mixfix_term  [TERM]
	  | Mixfix_token Token -- all kind of brackets are included
	  | Mixfix_sorted_term [TERM] [Token]
	    -- [Token] contains: colon and sort
	  | Mixfix_cast [TERM] [Token]
	    -- [Token] contains: "as" and sort
	  | Mixfix_cond [TERM] FORMULA [TERM] [Pos]
	    -- pos: when, else
	    deriving (Show,Eq)

data OP_SYMB = Op_name OP_NAME
	     | Qual_op_name OP_NAME OP_TYPE
		 -- pos: "(", op, colon, ")"
	       deriving (Show,Eq)

type OP_NAME = Id

type PRED_NAME = Id

type SORT = Token 

type VAR = SIMPLE_ID

----- 
data SYMB_ITEMS = Symb_items SYMB_KIND [SYMB] [Pos] 
		  -- pos: SYMB_KIND, commas
		  deriving (Show,Eq)

data SYMB_MAP_ITEMS = Symb_map_items SYMB_KIND [SYMB_OR_MAP] [Pos]
		      -- pos: SYMB_KIND, commas
		      deriving (Show,Eq)

data SYMB_KIND = Implicit | Sorts_kind 
	       | Ops_kind | Preds_kind
		 deriving (Show,Eq)

data SYMB = Symb_id Id
	  | Qual_id Id TYPE [Pos] 
	    -- pos: colon
	    deriving (Show,Eq)

data TYPE = O_type OP_TYPE
	  | P_type PRED_TYPE
	    deriving (Show,Eq)

data SYMB_OR_MAP = Symb SYMB
		 | Symb_map SYMB SYMB [Pos]
		   -- pos: "|->"
		   deriving (Show,Eq)