local Point3=_radiant.csg.Point3
local Cube3=_radiant.csg.Cube3

local search = class()

function search:__init()
    self.name = {}
    self.radius = 1
    self.tags = ""
    self.uris = ""
    self.scripts = {}
end

function search:parse(jsonsearch)
    self.name = jsonsearch;
    self.radius = jsonsearch.radius

    if jsonsearch.tags then
        for id,tag in pairs(jsonsearch.tags)do
            self.tags = self.tags .. tag
        end      
    end

    if jsonsearch.uris then
        for id,uri in pairs(jsonsearch.uris)do
            self.uris = self.uris .. uri
        end      
    end

    if jsonsearch.scripts then
        local index = 1
        for id,script in pairs(jsonsearch.scripts)do
            self.scripts[index] = radiant.mods.load_script(script)
            index = index + 1
        end
    end

    return self;
end

function search:contains(uri, tag)
    if uri and self.uris and string.find(self.uris, uri) then
        return true
    end

    if tag and self.tags and string.find(self.tags, tag) then
        return true
    end
    return false
end

function search:callbacks(searching_entity, entity)
    for id,script in pairs(self.scripts)do
           script.onfound(searching_entity, entity)
    end
end

local EntitySearcherComponent=class()

function EntitySearcherComponent:initialize(entity,json)
    self._entity=entity


    if self._sv._initialized then

        radiant.events.listen(radiant,'radiant:game_loaded',
            function(e)
                self._position_trace=radiant.entities.trace_location(self._entity,'entity forms component'):on_changed(
                    function()
                        self:_on_position_changed()
                end)

            return radiant.events.UNLISTEN
        end)
    else
        self._sv._initialized = true

        if json.searchers then
            self.searchers = {}
            self:parse_seachers(json.searchers)
        end

        self.__saved_variables:mark_changed()

        self._position_trace=radiant.entities.trace_location(self._entity,'entity forms component'):on_changed(
            function()
                self:_on_position_changed()
            end)
    end
end

function EntitySearcherComponent:destroy()
    self:endsearcher()
end

function EntitySearcherComponent:parse_seachers( json )
    local index = 1
    for id,s in pairs(json)do
        self.searchers[index] = search():parse(s)
        index = index + 1
    end
end

function EntitySearcherComponent:_on_position_changed()
    if self._entity:get_component('mob'):get_parent() then
        self:startsearcher()
    else
        self:endsearcher()
    end

end

function EntitySearcherComponent:startsearcher()
    if self._timer ==  nil then
        self._timer=stonehearth.calendar:set_interval('5m',
        function()
            self:dosearch()
        end)
    end
end

function EntitySearcherComponent:endsearcher()
    if self._timer then
        self._timer:destroy()
        self._timer=nil
    end
end

function EntitySearcherComponent:dosearch()
 
    local pos = self._entity:add_component('mob'):get_grid_location()
    for id,s in pairs(self.searchers)do

        local cube=Cube3(pos+Point3(-s.radius,0,-s.radius),pos+Point3(s.radius+1,1,s.radius+1))

        local entities=radiant.terrain.get_entities_in_cube(cube)
        for id,entity in pairs(entities)do
            local uri = entity:get_uri()
            local tags
            local material = entity:get_component("stonehearth:material")
            if material then
                tags = material:get_tags()
            end

            if s:contains(uri, tags) then
                s:callbacks(self._entity, entity)
            end

        end
    end
end

            --if string.find(uri, "plants") then
--            --    --radiant.entities.destroy_entity(entity)
--            --end
--
--            --local item = entity:get_component("item")
--            --local unitinfo = entity:get_component("unit_info")
--
--            --if item and item:get_category() == "plants" then
--            --    radiant.dostuff()
--            --end
--
--            --if unitinfo then
--            --    local name = unitinfo:get_display_name()
--            --    if string.find(name,"Brightbell Flower") then
--            --        radiant.dostuff()
--            --    end
--
--            --    
--            --end
--
--            --local entforms = entity:get_component('stonehearth:entity_forms')
--            --if entforms then
--            --    local entinworld = entforms:_get_form_in_world();
--
--            --    local unt = entinworld:get_component("unit_info")
--            --    local n = unt:get_display_name()
--
            --    if string.find(n, "Brightbell") then
            --        radiant.dostuff()
            --    end
            --end
            --h = id;

return EntitySearcherComponent
