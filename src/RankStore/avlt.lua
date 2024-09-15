local AVLTree = {}
AVLTree.__index = AVLTree

local Node = {}
Node.__index = Node

function Node.New(id, score)
    return setmetatable({
        id = id,
        score = score,
        height = 1,
        left = nil,
        right = nil
    }, Node)
end

function AVLTree.New()
    return setmetatable({
        root = nil,
        size = 0
    }, AVLTree)
end

local function Height(node)
    return node and node.height or 0
end

local function UpdateHeight(node)
    node.height = 1 + math.max(Height(node.left), Height(node.right))
end

local function BalanceFactor(node)
    return Height(node.left) - Height(node.right)
end

local function RotateRight(y)
    local x = y.left
    local T2 = x.right

    x.right = y
    y.left = T2

    UpdateHeight(y)
    UpdateHeight(x)

    return x
end

local function RotateLeft(x)
    local y = x.right
    local T2 = y.left

    y.left = x
    x.right = T2

    UpdateHeight(x)
    UpdateHeight(y)

    return y
end

function AVLTree:Insert(id, score)
    local function InsertRec(node, id, score)
        if not node then
            self.size = self.size + 1
            return Node.New(id, score)
        end

        if score < node.score or (score == node.score and id < node.id) then
            node.left = InsertRec(node.left, id, score)
        else
            node.right = InsertRec(node.right, id, score)
        end

        UpdateHeight(node)

        local balance = BalanceFactor(node)

        if balance > 1 then
            if score < node.left.score or (score == node.left.score and id < node.left.id) then
                return RotateRight(node)
            else
                node.left = RotateLeft(node.left)
                return RotateRight(node)
            end
        end

        if balance < -1 then
            if score > node.right.score or (score == node.right.score and id > node.right.id) then
                return RotateLeft(node)
            else
                node.right = RotateRight(node.right)
                return RotateLeft(node)
            end
        end

        return node
    end

    self.root = InsertRec(self.root, id, score)
end

function AVLTree:Remove(id, score)
    local function FindMin(node)
        local current = node
        while current.left do
            current = current.left
        end
        return current
    end

    local function RemoveRec(node, id, score)
        if not node then
            return nil
        end

        if score < node.score or (score == node.score and id < node.id) then
            node.left = RemoveRec(node.left, id, score)
        elseif score > node.score or (score == node.score and id > node.id) then
            node.right = RemoveRec(node.right, id, score)
        else
            if not node.left or not node.right then
                local temp = node.left or node.right
                if not temp then
                    temp = nil
                end
                self.size = self.size - 1
                return temp
            else
                local temp = FindMin(node.right)
                node.id = temp.id
                node.score = temp.score
                node.right = RemoveRec(node.right, temp.id, temp.score)
            end
        end

        if not node then
            return nil
        end

        UpdateHeight(node)

        local balance = BalanceFactor(node)

        if balance > 1 then
            if BalanceFactor(node.left) >= 0 then
                return RotateRight(node)
            else
                node.left = RotateLeft(node.left)
                return RotateRight(node)
            end
        end

        if balance < -1 then
            if BalanceFactor(node.right) <= 0 then
                return RotateLeft(node)
            else
                node.right = RotateRight(node.right)
                return RotateLeft(node)
            end
        end

        return node
    end

    self.root = RemoveRec(self.root, id, score)
end

function AVLTree:Search(id, score)
    local function SearchRec(node, id, score)
        if not node then
            return nil
        end

        if score == node.score and id == node.id then
            return node
        elseif score < node.score or (score == node.score and id < node.id) then
            return SearchRec(node.left, id, score)
        else
            return SearchRec(node.right, id, score)
        end
    end

    return SearchRec(self.root, id, score)
end

function AVLTree:InorderTraversal()
    local result = {}
    local function InorderRec(node)
        if node then
            InorderRec(node.left)
            table.insert(result, {id = node.id, score = node.score})
            InorderRec(node.right)
        end
    end
    InorderRec(self.root)
    return result
end

return AVLTree
