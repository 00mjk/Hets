import Proofs.Proofs
import Common.ATerm.Lib
import Comorphisms.LogicGraph
import Logic.Logic

instance ATermConvertible BasicProof where
     toShATerm att0 (BasicProof lid p) = 
	 case toShATerm att0 (language_name lid) of { (att1,i1) ->
         case toShATerm att1 p of { (att2,i2) ->
            addATerm (ShAAppl "BasicProof" [i1,i2] []) att2}}
     toShATerm att0 Guessed =
         case toShATerm att0 (show Guessed) of { (att1, i1) ->
            addATerm (ShAAppl "BasicProof" [i1] []) att1}
     toShATerm att0 Conjectured =
         case toShATerm att0 (show Conjectured) of { (att1, i1) ->
            addATerm (ShAAppl "BasicProof" [i1] []) att1}
     toShATerm att0 Handwritten =
         case toShATerm att0 (show Handwritten) of { (att1, i1) ->
            addATerm (ShAAppl "BasicProof" [i1] []) att1}

     fromShATerm att = 
         case aterm of
	    (ShAAppl "BasicProof" [i1,i2] _) ->
	       case fromShATerm (getATermByIndex1 i1 att) of { i1' ->
               case getATermByIndex1 i2 att of { att' ->
               case lookupLogic_in_LG 
                        ("ATermConvertible BasicProof") i1'  of {
                    Logic lid -> (BasicProof lid (fromShATerm att'))}}}
            v@(ShAAppl "BasicProof" [i1] _) ->
               case fromShATerm (getATermByIndex1 i1 att) of { i1' ->
               case i1' of
                 "Guessed" -> Guessed
                 "Conjectured" -> Conjectured
                 "Handwritten" -> Handwritten
                 _ -> fromShATermError "BasicProof" v}
	    u     -> fromShATermError "BasicProof" u
         where
         aterm = getATerm att
     fromATerm _ = fromATermErr "BasicProof"
     toATerm _ = toATermErr "BasicProof"



instance ATermConvertible (Proof_status proof_tree) where
     toShATerm att0 ps =
--	 case toShATerm att0 proof_tree of { (att1,i1) ->
         case toShATerm att0 ps of { (att1,i1) ->
            addATerm (ShAAppl "Proof_status proof_tree" [i1] []) att1}
     fromShATerm att = 
         case aterm of
	    (ShAAppl "Proof_status proof_tree" [i1] _) ->
	       case fromShATerm (getATermByIndex1 i1 att) of { i1' ->
--               case formShATerm (getATermByIndex1 i2 att) of { i2' ->
                 i1'}
  --                  (Proof_status i1')}
	    u     -> fromShATermError "Proof_status proof_tree" u
         where
         aterm = getATerm att
     fromATerm _ = fromATermErr "Proof_status proof_tree"
     toATerm _ = toATermErr "Proof_status proof_tree"

