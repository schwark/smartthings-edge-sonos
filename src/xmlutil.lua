local M = {}

---Gets an _attr element from a table that represents the attributes of an XML tag,
--and generates a XML String representing the attibutes to be inserted
--into the openning tag of the XML
--
--@param attrTable table from where the _attr field will be got
--@return a XML String representation of the tag attributes
local function attrToXml(attrTable)
  local s = ""
  attrTable = attrTable or {}
  
  for k, v in pairs(attrTable) do
      s = s .. " " .. k .. "=" .. '"' .. v .. '"'
  end
  return s
end

---Gets the first key of a given table
local function getFirstKey(tb)
   if type(tb) == "table" then
      for k, _ in pairs(tb) do
          return k
      end
      return nil
   end

   return tb
end

--- Parses a given entry in a lua table
-- and inserts it as a XML string into a destination table.
-- Entries in such a destination table will be concatenated to generated
-- the final XML string from the origin table.
-- @param xmltb the destination table where the XML string from the parsed key will be inserted
-- @param tagName the name of the table field that will be used as XML tag name
-- @param fieldValue a field from the lua table to be recursively parsed to XML or a primitive value that will be enclosed in a tag name
-- @param level a int value used to include indentation in the generated XML from the table key
local function parseTableKeyToXml(xmltb, tagName, fieldValue, level)
    local spaces = string.rep(' ', level*2)

    local strValue, attrsStr = "", ""
    if type(fieldValue) == "table" then
        attrsStr = attrToXml(fieldValue._attr)
        fieldValue._attr = nil
        --If after removing the _attr field there is just one element inside it,
        --the tag was enclosing a single primitive value instead of other inner tags.
        strValue = #fieldValue == 1 and spaces..tostring(fieldValue[1]) or M.toXml(fieldValue, tagName, level+1)
        strValue = '\n'..strValue..'\n'..spaces
    else
        strValue = tostring(fieldValue)
    end

    table.insert(xmltb, spaces..'<'..tagName.. attrsStr ..'>'..strValue..'</'..tagName..'>')
end

---Converts a Lua table to a XML String representation.
--@param tb Table to be converted to XML
--@param tableName Name of the table variable given to this function,
--                 to be used as the root tag. If a value is not provided
--                 no root tag will be created.
--@param level Only used internally, when the function is called recursively to print indentation
--
--@return a String representing the table content in XML
function M.toXml(tb, tableName, level)
  level = level or 1
  local firstLevel = level
  tableName = tableName or ''
  local xmltb = (tableName ~= '' and level == 1) and {'<'..tableName..attrToXml(tb._attr)..'>'} or {}
  tb._attr = nil

  for k, v in pairs(tb) do
      if type(v) == 'table' then
         -- If the key is a number, the given table is an array and the value is an element inside that array.
         -- In this case, the name of the array is used as tag name for each element.
         -- So, we are parsing an array of objects, not an array of primitives.
         if type(k) == 'number' then
            parseTableKeyToXml(xmltb, tableName, v, level)
         else
            level = level + 1
            -- If the type of the first key of the value inside the table
            -- is a number, it means we have a HashTable-like structure,
            -- in this case with keys as strings and values as arrays.
            if type(getFirstKey(v)) == 'number' then
                for sub_k, sub_v in pairs(v) do
                    if sub_k ~= '_attr' then
                      local sub_v_with_attr = type(v._attr) == 'table' and { sub_v, _attr = v._attr } or sub_v
                      parseTableKeyToXml(xmltb, k, sub_v_with_attr, level)
                    end
                end
            else
               -- Otherwise, the "HashTable" values are objects
               parseTableKeyToXml(xmltb, k, v, level)
            end
         end
      else
         -- When values are primitives:
         -- If the type of the key is number, the value is an element from an array.
         -- In this case, uses the array name as the tag name.
         if type(k) == 'number' then
            k = tableName
         end
         parseTableKeyToXml(xmltb, k, v, level)
      end
  end

  if tableName ~= '' and firstLevel == 1 then
      table.insert(xmltb, '</'..tableName..'>\n')
  end

  return table.concat(xmltb, '\n')
end

function M.xml_decode(str)
    str = str:gsub('&lt;', '<' )
    str = str:gsub('&gt;', '>' )
    str = str:gsub('&quot;', '"' )
    str = str:gsub('&apos;', "'" )
    str = str:gsub('&#(%d+);', function(n) return string.char(n) end )
    str = str:gsub('&#x(%d+);', function(n) return string.char(tonumber(n,16)) end )
    str = str:gsub('&amp;', '&' ) -- Be sure to do this after all others
    return str
end

function M.xml_encode(str)
    if type(str) == "boolean" then
        str = str and "1" or "0"
    end
    str = tostring(str)
    str = str:gsub('&', '&amp;') -- Be sure to do this before all others
    str = str:gsub('<' ,'&lt;')
    str = str:gsub('>' ,'&gt;')
    str = str:gsub('"' ,'&quot;')
    str = str:gsub("'" ,'&apos;')
    return str
end

function M.tight_xml(xml)
    xml = xml:gsub('>%s+','>')
    xml = xml:gsub('%s+<','<')
    return xml
end



return M