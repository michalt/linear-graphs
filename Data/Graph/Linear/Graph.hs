{-# LANGUAGE TypeFamilies #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Graph.Linear.Graph
-- Copyright   :  
-- License     :  BSD-style (see the file LICENSE)
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  experimental
-- Portability :  portable
--
-- Data.Graph.Linear.Basic implements various representation and convenience
-- constructors for linear time and space graph algorithms.
--
-----------------------------------------------------------------------------
--
module Data.Graph.Linear.Graph
(
    Bounds, Vertex, Edge
  , Node(..)
  , GraphRepresentation(..)
  , Graph(..)
  , graphFromEdgedVertices, nodeConstructor
) 
where

{- #ifdef USE_VECTOR
import Data.Graph.Linear.Representation.Vector as Rep
 #else-}
import Data.Graph.Linear.Representation.Array as Rep
-- #endif

import Data.Maybe(mapMaybe)
import Data.List

-------------------------------------------------------------------------------
-- Internal Graph Representation

-- | A single Vertex represented in an InternalGraph.
type Vertex        = Int

-- | A single edge between any two representations of points in a graph.
type Edge n        = (n, n)

-- | An internal-only adjacency list mapping from Vertices to neighboring vertices.
type InternalGraph = Rep.Mapping [Vertex]

-------------------------------------------------------------------------------
-- External Graph Representation

-- | A single 'Node' represents an addressable vertex within a 'Graph'. The choice
-- of information stored at the node, as well as the label addressing each node is
-- kept polymorphic.
data Node payload label = Node
  { payload    :: payload  -- ^ The information stored at this point in the graph
  , label      :: !label   -- ^ The label for this node
  , successors :: ![label] -- ^ List of labeled edges rechable from this node.
  }

instance Eq l => Eq (Node p l) where
  (==) (Node _ l1 _) (Node _ l2 _) = l1 == l2 
  (/=) (Node _ l1 _) (Node _ l2 _) = l1 /= l2

instance Ord l => Ord (Node p l) where
  compare (Node _ l1 _) (Node _ l2 _)
          | l1 == l2   = EQ
          | l1 <= l2   = LT
          | otherwise = GT

instance (Show p, Show l) => Show (Node p l) where
  show (Node p l ls) = show p ++ "[" ++  show l ++ "]"
-------------------------------------------------------------------------------
-- Constructors

-- | Given an arbitrary representation of a set of nodes, we can construct a graph.
class Ord node => GraphRepresentation node where
  -- | The Graph data type, polymorphic in the type of node.
  data Graph node :: *

  -- |The empty graph.
  empty      :: Graph node

  -- |Given a list of nodes, we can construct a graph.
  mkGraph    :: [node]     -> Graph node

  -- |List of nodes in this graph.
  nodes      :: Graph node -> [node]

  -- |List of vertices in this graph.
  vertices   :: Graph node -> [Vertex]

  -- |List of edges between nodes in this graph.
  edges      :: Graph node -> [Edge node]

  -- |List of edges between vertices in this graph.
  vedges     :: Graph node -> [Edge Vertex]

  -- |Return the vertices adjacent to a given node in this graph.
  adjacentTo :: Graph node -> Vertex -> [Vertex]

  -- |Return the upper and lower bounds on the vertex-numbering of this graph's
  -- representation
  bounds     :: Graph node -> Bounds

instance Ord l => GraphRepresentation (Node p l) where 
  data Graph (Node p l)    = Graph 
    { grAdjacencyList :: {-# UNPACK #-} !InternalGraph
    , grVertexMap     :: Vertex -> Node p l
    , grNodeMap       :: Node p l -> Maybe Vertex
    }

  empty                    = Graph Rep.empty (error "emptyGraph") (const Nothing)
  mkGraph nodes            = Graph intgraph vertex_fn (label_vertex . label)
    where
      (bounds, vertex_fn, label_vertex, numbered_nodes) = reduceNodesIntoVertices nodes label

      reduceNodesIntoVertices nodes label_extractor = (bounds, (!) vertex_map, label_vertex, numbered_nodes)
        where
          max_v           = length nodes - 1
          bounds          = (0, max_v)

          sorted_nodes    = let n1 `le` n2 = (label_extractor n1 `compare` label_extractor n2)
                            in sortBy le nodes

          numbered_nodes  = [0..] `zip` sorted_nodes

          key_map         = Rep.mkMap bounds [(v, label_extractor node) | (v, node) <- numbered_nodes]
          vertex_map      = Rep.mkMap bounds numbered_nodes

          --label_vertex :: label -> Maybe Vertex
          -- returns Nothing for non-interesting vertices
          label_vertex k = find 0 max_v
            where
              find a b | a > b     = Nothing
                       | otherwise = let mid = (a + b) `div` 2
                                     in case compare k (key_map ! mid) of
                                          LT -> find a (mid - 1)
                                          EQ -> Just mid
                                          GT -> find (mid + 1) b

      intgraph = Rep.mkMap bounds [(v, mapMaybe label_vertex ks) | (v, Node _ _ ks) <- numbered_nodes]

  nodes     (Graph g vm _) = map vm (domain g)
  vertices  (Graph g vm _) = domain g
  edges     (Graph g vm _) = [ (vm v, vm w) | v <- domain g, w <- g ! v ]
  vedges    (Graph g _ _)  = [ (v, w) | v <- domain g, w <- g ! v ]
  adjacentTo (Graph g _ _) = (!) g
  bounds    (Graph g _ _)  = domainBounds g


-- |Helper function for constructing graphs out of lists of tuples.
graphFromEdgedVertices :: Ord label => [(payload, label, [label])] -> Graph (Node payload label)
graphFromEdgedVertices = mkGraph . map nodeConstructor

-- |A helper function for constructing Node representations out of tuples.
nodeConstructor :: Ord l => (p, l, [l]) -> Node p l
nodeConstructor = \(p, l, ls) -> Node p l ls
