-- AVL Tree implementation with GetIndex(rank) function
local Tree = {}
local ClassVariables = {}

--[[
    Constructs a tree
    @param Init     An unordered list of pairs of {Value, Extra} to insert into the tree
    @return the tree object
]]
Tree.New = function(Init)
    local self = {}
    setmetatable(self, { __index = ClassVariables })

    self.Root = nil
    if Init ~= nil then
        for _, NodeData in ipairs(Init) do
            if type(NodeData) == "table" then
                self.Root = Tree.Insert(self.Root, unpack(NodeData))
            else
                self.Root = Tree.Insert(self.Root, NodeData)
            end
        end
    end

    return self
end

--[[
    Constructs an AVL tree from an ordered array
    @param OrderedArray    An array of {Value, Extra} pairs (or just Values) sorted in ascending order
    @return An AVL tree object
]]
function Tree.FromOrderedArray(OrderedArray)
    local self = {}
    setmetatable(self, { __index = ClassVariables })

    -- Internal recursive function to build the tree
    local function BuildTree(array, startIdx, endIdx)
        if startIdx > endIdx then
            return nil
        end

        local midIdx = math.floor((startIdx + endIdx) / 2)
        local NodeData = array[midIdx]
        local Value, Extra

        if type(NodeData) == "table" then
            Value, Extra = NodeData[1], NodeData[2]
        else
            Value = NodeData
            Extra = nil
        end

        local root = Node(Value, Extra)
        root.Left = BuildTree(array, startIdx, midIdx - 1)
        root.Right = BuildTree(array, midIdx + 1, endIdx)

        -- Update height
        root.Height = 1 + math.max(
            Tree.GetHeight(root.Left),
            Tree.GetHeight(root.Right)
        )

        -- Update size
        root.Size = 1 + Tree.GetSize(root.Left) + Tree.GetSize(root.Right)

        return root
    end

    self.Root = BuildTree(OrderedArray, 1, #OrderedArray)
    return self
end

--[[
    Inserts a node into the tree
    @param Value    The value to insert
    @param Extra    Optional. Extra data to store in the node
]]
function ClassVariables:Insert(...)
	local newRoot, insertedNode, rank = Tree.Insert(self.Root, ...)
	self.Root = newRoot
	return insertedNode, rank
end

--[[
    Retrieves the rank where a new node would be inserted
    @param Value    The value to insert
    @return The rank of the node if it were to be inserted
]]
function ClassVariables:GetInsertRank(...)
    return Tree.GetInsertRank(self.Root, ...)
end

--[[
    Removes a node from the tree
    @param Value    The value to remove
]]
function ClassVariables:Remove(...)
    local newRoot, removedNode, rank = Tree.Remove(self.Root, ...)
    self.Root = newRoot
    return removedNode, rank
end

--[[
    Retrieves a node by its value
    @param Value    The value to search for
    @return The node or nil if not found
]]
function ClassVariables:Get(...)
    return Tree.Get(self.Root, ...)
end

--[[
    Retrieves the node at the given sorted index
    @param rank     The sorted index (1-based)
    @return The node at the specified index or nil if out of bounds
]]
function ClassVariables:GetIndex(rank, reverse)
    return Tree.GetIndex(self.Root, rank, reverse)
end

--[[
    Retrieves the size of the tree (total number of nodes)
    @return The size of the tree
]]
function ClassVariables:GetSize()
    return Tree.GetSize(self.Root)
end

function ClassVariables:Iterator(reverse)
	reverse = (reverse == nil) and false or reverse

    local stack = {}
    local current = self.Root

    return function()
        while current ~= nil or #stack > 0 do
            if current ~= nil then
                table.insert(stack, current)
				if reverse then
					current = current.Right
				else
					current = current.Left
				end
            else
                current = table.remove(stack)
                local node = current
				if reverse then
					current = current.Left
				else
					current = current.Right
				end
                return node
            end
        end
        return nil  -- Iteration complete
    end
end

--[[
    Constructs a Node
    @param Value    The value of the node
    @param Extra    Optional. Extra data to store in the node
    @return A Node instance
]]
Node = function(Value, Extra)
    local self = {}

    self.Value = Value
    self.Extra = Extra
    self.Left = nil
    self.Right = nil
    self.Height = 1
    self.Size = 1  -- Initialize size to 1 for the new node

    return self
end

--[[
    Inserts a new node into the tree rooted at Root
    @param Root             The root of the tree/subtree
    @param Value            The value to insert
    @param Extra            Optional. Extra data to store in the node
    @param cumulativeRank   Optional. The rank accumulated so far
    @return The new root of the subtree, the inserted node, and its rank
]]
function Tree.Insert(Root, Value, Extra, cumulativeRank)
    cumulativeRank = cumulativeRank or 0
    local insertedNode
    local rank

    -- Create a new node if the root doesn't exist
    if Root == nil then
        insertedNode = Node(Value, Extra)
        rank = cumulativeRank + 1
        return insertedNode, insertedNode, rank
    end

    -- Insert into left or right subtree
    if Value < Root.Value then
        Root.Left, insertedNode, rank = Tree.Insert(Root.Left, Value, Extra, cumulativeRank)
    else
        cumulativeRank = cumulativeRank + Tree.GetSize(Root.Left) + 1
        Root.Right, insertedNode, rank = Tree.Insert(Root.Right, Value, Extra, cumulativeRank)
    end

    -- Update the height and size of the ancestor node
    Root.Height = 1 + math.max(
        Tree.GetHeight(Root.Left),
        Tree.GetHeight(Root.Right)
    )
    Root.Size = 1 + Tree.GetSize(Root.Left) + Tree.GetSize(Root.Right)

    -- Get the balance factor
    local Balance = Tree._GetBalance(Root)

    -- Balance the tree if unbalanced
    -- Left Left Case
    if (Balance > 1) and (Value < Root.Left.Value) then
        return RightRotate(Root), insertedNode, rank
    end

    -- Right Right Case
    if (Balance < -1) and (Value > Root.Right.Value) then
        return LeftRotate(Root), insertedNode, rank
    end

    -- Left Right Case
    if (Balance > 1) and (Value > Root.Left.Value) then
        Root.Left = LeftRotate(Root.Left)
        return RightRotate(Root), insertedNode, rank
    end

    -- Right Left Case
    if (Balance < -1) and (Value < Root.Right.Value) then
        Root.Right = RightRotate(Root.Right)
        return LeftRotate(Root), insertedNode, rank
    end

    return Root, insertedNode, rank
end

-- Tree.GetInsertRank function: Returns the rank where a new node would be inserted
-- @param Root     The root of the tree/subtree
-- @param Value    The value to insert
-- @param cumulativeRank Optional. The rank accumulated so far
-- @return         The rank of the node if it were to be inserted
function Tree.GetInsertRank(Root, Value, cumulativeRank)
    cumulativeRank = cumulativeRank or 0

    if Root == nil then
        return cumulativeRank + 1
    end

    if Value < Root.Value then
        return Tree.GetInsertRank(Root.Left, Value, cumulativeRank)
    else
        cumulativeRank = cumulativeRank + Tree.GetSize(Root.Left) + 1
        return Tree.GetInsertRank(Root.Right, Value, cumulativeRank)
    end
end

--[[
    Removes a node from the tree rooted at Root
    @param Root             The root of the tree/subtree
    @param Value            The value to remove
    @param cumulativeRank   Optional. The rank accumulated so far
    @return The new root of the subtree, the removed node, and its rank
]]
function Tree.Remove(Root, Value, Extra, cumulativeRank)
    cumulativeRank = cumulativeRank or 0
    local removedNode
    local rank

    -- Return nil if the root doesn't exist
    if Root == nil then
        return nil, nil, nil
    end

    -- Traverse the tree to find the node to remove
    if Value < Root.Value then
        Root.Left, removedNode, rank = Tree.Remove(Root.Left, Value, Extra, cumulativeRank)
    elseif Value > Root.Value then
        cumulativeRank = cumulativeRank + Tree.GetSize(Root.Left) + 1
        Root.Right, removedNode, rank = Tree.Remove(Root.Right, Value, Extra, cumulativeRank)
    else
        -- Value matches, check Extra
        if Root.Extra == Extra then
            -- Node to be deleted found
            removedNode = Root
            rank = cumulativeRank + Tree.GetSize(Root.Left) + 1

            -- Node with only one child or no child
            if Root.Left == nil then
                return Root.Right, removedNode, rank
            elseif Root.Right == nil then
                return Root.Left, removedNode, rank
            end

            -- Node with two children
            -- Get the inorder successor (smallest in the right subtree)
            local Temp = Tree.GetLowestValueNode(Root.Right)

            -- Copy the inorder successor's content to this node
            Root.Value = Temp.Value
            Root.Extra = Temp.Extra

            -- Delete the inorder successor
            Root.Right, _, _ = Tree.Remove(Root.Right, Temp.Value, Temp.Extra, cumulativeRank + Tree.GetSize(Root.Left) + 1)
        else
            -- Extra doesn't match, continue searching both subtrees
            Root.Left, removedNode, rank = Tree.Remove(Root.Left, Value, Extra, cumulativeRank)
            if removedNode == nil then
                cumulativeRank = cumulativeRank + Tree.GetSize(Root.Left) + 1
                Root.Right, removedNode, rank = Tree.Remove(Root.Right, Value, Extra, cumulativeRank)
            end
        end
    end

    -- If node was removed from a subtree, update this node's properties and balance
    if removedNode then
        -- Update the height of the current node
        Root.Height = 1 + math.max(
            Tree.GetHeight(Root.Left),
            Tree.GetHeight(Root.Right)
        )

        -- Update the size of the current node
        Root.Size = 1 + Tree.GetSize(Root.Left) + Tree.GetSize(Root.Right)

        -- Get the balance factor
        local Balance = Tree._GetBalance(Root)

        -- Balance the tree if unbalanced
        -- Left Left Case
        if (Balance > 1) and (Tree._GetBalance(Root.Left) >= 0) then
            return RightRotate(Root), removedNode, rank
        end

        -- Left Right Case
        if (Balance > 1) and (Tree._GetBalance(Root.Left) < 0) then
            Root.Left = LeftRotate(Root.Left)
            return RightRotate(Root), removedNode, rank
        end

        -- Right Right Case
        if (Balance < -1) and (Tree._GetBalance(Root.Right) <= 0) then
            return LeftRotate(Root), removedNode, rank
        end

        -- Right Left Case
        if (Balance < -1) and (Tree._GetBalance(Root.Right) > 0) then
            Root.Right = RightRotate(Root.Right)
            return LeftRotate(Root), removedNode, rank
        end
    end

    return Root, removedNode, rank
end


--[[
    Retrieves the height of a node
    @param Node     The node
    @return The height of the node or 0 if nil
]]
function Tree.GetHeight(Node)
    if Node == nil then
        return 0
    else
        return Node.Height
    end
end

--[[
    Retrieves the size of a node's subtree
    @param Node     The node
    @return The size of the node's subtree or 0 if nil
]]
function Tree.GetSize(Node)
    if Node == nil then
        return 0
    else
        return Node.Size
    end
end

--[[
    Retrieves a node by its value and extra parameter, along with its rank
    @param Root           The root of the tree/subtree
    @param Value          The value to search for
    @param Extra          The extra parameter to match against the node's extra value
    @param cumulativeRank Optional. The rank accumulated so far
    @return The node and its rank or nil if not found
]]
function Tree.Get(Root, Value, Extra, cumulativeRank)
    cumulativeRank = cumulativeRank or 0
    if Root == nil then
        return nil, nil
    end

    local leftSize = Tree.GetSize(Root.Left)

    if Value < Root.Value then
        return Tree.Get(Root.Left, Value, Extra, cumulativeRank)
    elseif Value > Root.Value then
        return Tree.Get(Root.Right, Value, Extra, cumulativeRank + leftSize + 1)
    else -- Value == Root.Value
        local totalRank = cumulativeRank + leftSize + 1
        if Root.Extra == Extra then
            return Root, totalRank
        else
            -- Search left subtree
            local leftResult, leftRank = Tree.Get(Root.Left, Value, Extra, cumulativeRank)
            if leftResult ~= nil then
                return leftResult, leftRank
            end
            -- Search right subtree
            return Tree.Get(Root.Right, Value, Extra, cumulativeRank + leftSize + 1)
        end
    end
end

--[[
    Retrieves the node at the given sorted index
    @param Root     The root of the tree/subtree
    @param rank     The sorted index (1-based)
    @return The node at the specified index or nil if out of bounds
]]
function Tree.GetIndex(Root, rank, reverse)
    reverse = reverse or false
    if Root == nil then
        return nil
    end

    local leftSize = Tree.GetSize(Root.Left)
    local rightSize = Tree.GetSize(Root.Right)

    if not reverse then
        if rank == leftSize + 1 then
            return Root
        elseif rank <= leftSize then
            return Tree.GetIndex(Root.Left, rank, false)
        else
            return Tree.GetIndex(Root.Right, rank - leftSize - 1, false)
        end
    else
        if rank == rightSize + 1 then
            return Root
        elseif rank <= rightSize then
            return Tree.GetIndex(Root.Right, rank, true)
        else
            return Tree.GetIndex(Root.Left, rank - rightSize - 1, true)
        end
    end
end

--[[
    Calculates the balance factor of a node
    @param Node     The node
    @return The balance factor (height difference between left and right subtrees)
]]
function Tree._GetBalance(Node)
    if Node == nil then
        return 0
    else
        return Tree.GetHeight(Node.Left) - Tree.GetHeight(Node.Right)
    end
end

--[[
    Finds the node with the smallest value in a subtree
    @param Node     The root of the subtree
    @return The node with the smallest value
]]
function Tree.GetLowestValueNode(Node)
    if (Node == nil) or (Node.Left == nil) then
        return Node
    else
        return Tree.GetLowestValueNode(Node.Left)
    end
end

--[[
    Performs a right rotation on the subtree rooted at Node0
    @param Node0    The root of the subtree
    @return The new root after rotation
]]
function RightRotate(Node0)
    local Node1 = Node0.Left
    local Node2 = Node1.Right

    -- Perform rotation
    Node1.Right = Node0
    Node0.Left = Node2

    -- Update heights
    Node0.Height = 1 + math.max(
        Tree.GetHeight(Node0.Left),
        Tree.GetHeight(Node0.Right)
    )
    Node1.Height = 1 + math.max(
        Tree.GetHeight(Node1.Left),
        Tree.GetHeight(Node1.Right)
    )

    -- Update sizes
    Node0.Size = 1 + Tree.GetSize(Node0.Left) + Tree.GetSize(Node0.Right)
    Node1.Size = 1 + Tree.GetSize(Node1.Left) + Tree.GetSize(Node1.Right)

    return Node1
end

--[[
    Performs a left rotation on the subtree rooted at Node0
    @param Node0    The root of the subtree
    @return The new root after rotation
]]
function LeftRotate(Node0)
    local Node1 = Node0.Right
    local Node2 = Node1.Left

    -- Perform rotation
    Node1.Left = Node0
    Node0.Right = Node2

    -- Update heights
    Node0.Height = 1 + math.max(
        Tree.GetHeight(Node0.Left),
        Tree.GetHeight(Node0.Right)
    )
    Node1.Height = 1 + math.max(
        Tree.GetHeight(Node1.Left),
        Tree.GetHeight(Node1.Right)
    )

    -- Update sizes
    Node0.Size = 1 + Tree.GetSize(Node0.Left) + Tree.GetSize(Node0.Right)
    Node1.Size = 1 + Tree.GetSize(Node1.Left) + Tree.GetSize(Node1.Right)

    return Node1
end

--[[
    Define the type for external use (if needed)
]]
export type typedef = typeof(Tree.New())

return Tree
