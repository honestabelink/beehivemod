local constants=require'constants'local Array2D=require'services.server.world_generation.array_2D'local BlueprintGenerator=require'services.server.world_generation.blueprint_generator'local personality_service=stonehearth.personality
local linear_combat_service=stonehearth.linear_combat
local Point2=_radiant.csg.Point2
local Point3=_radiant.csg.Point3
local Point3=_radiant.csg.Point3
local Rect2=_radiant.csg.Rect2
local Region2=_radiant.csg.Region2
local log=radiant.log.create_logger('world_generation')
local GENERATION_RADIUS=2
local NewGameCallHandler=class()
function NewGameCallHandler:sign_in(session,response,num_tiles_x,num_tiles_y,seed)
    local town=stonehearth.town:get_town(session.player_id)
    if not town then
        stonehearth.town:add_town(session)
        stonehearth.inventory:add_inventory(session)
        stonehearth.population:add_population(session,'stonehearth:kingdoms:ascendancy')
    end
    return
    {
        version=_radiant.sim.get_version()
    }
    
end

function NewGameCallHandler:set_game_options(session,response,options)
    linear_combat_service:enable(options.enable_enemies)
    return true
end

function NewGameCallHandler:new_game(session,response,num_tiles_x,num_tiles_y,seed,options)
    local wgs=stonehearth.world_generation
    local blueprint
    local tile_margin
    self:set_game_options(session,response,options)
    wgs:create_new_game(seed,true)
    local generation_method=radiant.util.get_config('world_generation.method','default')
    if generation_method=='tiny'then
        tile_margin=0
        blueprint=wgs.blueprint_generator:get_empty_blueprint(2,2)
        blueprint:get(1,1).terrain_type='mountains'
        blueprint:get(1,2).terrain_type='foothills'
    else
        tile_margin=GENERATION_RADIUS
        num_tiles_x=num_tiles_x+2*tile_margin
        num_tiles_y=num_tiles_y+2*tile_margin
        blueprint=wgs.blueprint_generator:generate_blueprint(num_tiles_x,num_tiles_y,seed)
    end
    wgs:set_blueprint(blueprint)
    return NewGameCallHandler:_get_overview_map(tile_margin)
end

function NewGameCallHandler:_get_overview_map(tile_margin)
    local wgs=stonehearth.world_generation
    local terrain_info=wgs:get_terrain_info()
    local width,
    height=wgs.overview_map:get_dimensions()
    local map=wgs.overview_map:get_map()
    local macro_blocks_per_tile=terrain_info.tile_size/terrain_info.macro_block_size
    local macro_block_margin=tile_margin*macro_blocks_per_tile
    local inset_width=width-2*macro_block_margin
    local inset_height=height-2*macro_block_margin
    local inset_map=Array2D(inset_width,inset_height)
    Array2D.copy_block(inset_map,map,1,1,1+macro_block_margin,1+macro_block_margin,inset_width,inset_height)
    local js_map=inset_map:clone_to_nested_arrays()
    local result=
    {
        map=js_map,
        map_info=
        {
            width=inset_width,
            height=inset_height,
            macro_block_margin=macro_block_margin
        }
    }
    
    return result
end

function NewGameCallHandler:generate_start_location(session,response,feature_cell_x,feature_cell_y,map_info)
    local wgs=stonehearth.world_generation
    feature_cell_x=feature_cell_x+1+map_info.macro_block_margin
    feature_cell_y=feature_cell_y+1+map_info.macro_block_margin
    local x,
    z=wgs.overview_map:get_coords_of_cell_center(feature_cell_x,feature_cell_y)
    wgs.generation_location=Point3(x,0,z)
    local radius=GENERATION_RADIUS
    local blueprint=wgs:get_blueprint()
    local i,
    j=wgs:get_tile_index(x,z)
    local generation_method=radiant.util.get_config('world_generation.method','default')
    if generation_method=='small'then
        radius=1
    end
    if blueprint.width>2*radius+1 then
        i=radiant.math.bound(i,1+radius,blueprint.width-radius)
    end
    if blueprint.height>2*radius+1 then
        j=radiant.math.bound(j,1+radius,blueprint.height-radius)
    end
    wgs:generate_tiles(i,j,radius)
    response:resolve({})
end

function NewGameCallHandler:embark_server(session,response)
    local scenario_service=stonehearth.scenario
    local wgs=stonehearth.world_generation
    local x=wgs.generation_location.x
    local z=wgs.generation_location.z
    local y=radiant.terrain.get_point_on_terrain(Point3(x,0,z)).y
    return
    {
        x=x,
        y=y,
        z=z
    }
    
end

function NewGameCallHandler:embark_client(session,response)
    _radiant.call('stonehearth:embark_server'):done(
    function(o)
        local camera_height=30
        local target_distance=70
        local camera_service=stonehearth.camera
        local target=Point3(o.x,o.y,o.z)
        local camera_location=Point3(target.x,target.y+camera_height,target.z+target_distance)
        camera_service:set_position(camera_location)
        camera_service:look_at(target)
        _radiant.call('stonehearth:get_visibility_regions'):done(
        function(o)
            log:info('Visible region uri: %s',o.visible_region_uri)
            log:info('Explored region uri: %s',o.explored_region_uri)
            stonehearth.renderer:set_visibility_regions(o.visible_region_uri,o.explored_region_uri)
            response:resolve({})
        end)
    end)
end

function NewGameCallHandler:choose_camp_location(session,response)
    stonehearth.selection:select_location():use_ghost_entity_cursor('stonehearth:camp_standard_ghost'):done(
    function(selector,location,rotation)
        local clip_height=self:_get_starting_clip_height(location)
        stonehearth.subterranean_view:set_clip_height(clip_height)
        _radiant.call('stonehearth:create_camp',location):done(
        function(o)
            response:resolve(
            {
                result=true,
                townName=o.random_town_name
            }
            )
        end):fail(
        function(result)
            response:reject(result)
        end):always(
        function()
            selector:destroy()
        end)
    end):fail(
    function(selector)
        selector:destroy()
        response:reject('no location')
    end):go()
end

function NewGameCallHandler:_get_starting_clip_height(starting_location)
    local step_size=constants.mining.Y_CELL_SIZE
    local quantized_height=math.floor(starting_location.y/step_size)*step_size
    local next_step=quantized_height+step_size
    local clip_height=next_step-1
    return clip_height
end

function NewGameCallHandler:create_camp(session,response,pt)
    stonehearth.world_generation:set_starting_location(Point2(pt.x,pt.z))
    local town=stonehearth.town:get_town(session.player_id)
    local pop=stonehearth.population:get_population(session.player_id)
    local random_town_name=town:get_town_name()
    local location=Point3(pt.x,pt.y,pt.z)
    local banner_entity=radiant.entities.create_entity('stonehearth:camp_standard')
    radiant.terrain.place_entity(banner_entity,location,
    {
            force_iconic=false
        }
        )
        town:set_banner(banner_entity)
        radiant.entities.turn_to(banner_entity,180)
        local camp_x=pt.x
        local camp_z=pt.z
        local function place_citizen_embark(x,z,job,talisman)
            local citizen=self:place_citizen(pop,x,z,job,talisman)
            radiant.events.trigger_async(personality_service,'stonehearth:journal_event',
            {
                entity=citizen,
                description='person_embarks'
            }
            )
            radiant.entities.turn_to(citizen,180)
            return citizen
        end

        -- stockpile code
        local box =
        {
            min = 
            {
                x = camp_x + 12,
                z = camp_z + 12
            },
            max = 
            {
                x = camp_x + 20,
                z = camp_z + 20
            }
        }

        local size=
        {
            x=box.max.x-box.min.x,
            y=box.max.z-box.min.z
        }

        local location = 
        {
            x = camp_x + 12,
            y=  pt.y,
            z = camp_z + 12
        }

        local inventory=stonehearth.inventory:get_inventory(session.player_id)
        local stockpile=inventory:create_stockpile(location,size)
        -- end stockpile

        local worker1=place_citizen_embark(camp_x-3,camp_z-3)
        local worker2=place_citizen_embark(camp_x+0,camp_z-3)
        local worker3=place_citizen_embark(camp_x+3,camp_z-3)
        local worker4=place_citizen_embark(camp_x-3,camp_z+3)
        local worker5=place_citizen_embark(camp_x+3,camp_z+3)
        local worker6=place_citizen_embark(camp_x-3,camp_z+0)
        local worker7=place_citizen_embark(camp_x+3,camp_z+0)

        -- extra workers
        -- change the 8 to a higher number for more
        for i = 6, 7 do
            local offset = i % 6 +6
            local worker8=place_citizen_embark(camp_x-offset,camp_z-offset)
            local worker9=place_citizen_embark(camp_x+0,camp_z-3)
            local worker10=place_citizen_embark(camp_x+offset,camp_z-offset)
            local worker11=place_citizen_embark(camp_x-offset,camp_z+offset)
            local worker12=place_citizen_embark(camp_x+offset,camp_z+offset)
            local worker13=place_citizen_embark(camp_x-offset,camp_z+0)
            local worker14=place_citizen_embark(camp_x+offset,camp_z+0)
        end
        -- end extra workers
        self:place_item(pop,'stonehearth:firepit',camp_x,camp_z+3,
        {
                force_iconic=false
            }
            )

            -- job talismans
            local carpenter_talisman = self:place_entity("stonehearth:carpenter:talisman", Point3(pt.x + 12, pt.y, pt.z + 12))
            local farmer_talisman =self:place_entity("stonehearth:farmer:talisman", Point3(pt.x + 13, pt.y, pt.z + 12))
            local weaver_talisman =self:place_entity("stonehearth:weaver:talisman", Point3(pt.x + 14, pt.y, pt.z + 12))
            local mason_talisman =self:place_entity("stonehearth:mason:talisman", Point3(pt.x + 14, pt.y, pt.z + 12))

            local beehive = self:place_entity("beehivemod:beehive", Point3(pt.x + 15, pt.y, pt.z + 12))
--            local beehive_testing = self:place_entity("beehivemod:beehive_testing", Point3(pt.x + 16, pt.y, pt.z + 12))
            local honey_pot = self:place_entity("beehivemod:honey_pot", Point3(pt.x + 17, pt.y, pt.z + 12))

            -- give some logs
            for i = 0, 4 do
                self:place_entity('stonehearth:resources:wood:oak_log', Point3(pt.x + 12, pt.y, pt.z + 16))
            end

            -- create carpenter
            -- place his workbench
            local carpenter = self:create_citizen_with_job(pop,"stonehearth:jobs:carpenter", carpenter_talisman, Point3(pt.x +3, pt.y, pt.z +3))
            self:create_job_workbench(carpenter, "stonehearth:carpenter:workbench", Point3(pt.x +11, pt.y, pt.z +12))

            return
            {
                random_town_name=random_town_name
            }
            
        end

        -- creates a hearthling with the specified job
        function NewGameCallHandler:create_citizen_with_job(pop,job_uri, talisman, location)
            local entity = self:place_citizen(pop, location.x, location.z, job_uri, talisman)
            return entity
        end

        -- tells a hearthling to make their workbench at location
        function NewGameCallHandler:create_job_workbench(citizen, workbench_uri, location)
            local workbench=radiant.entities.create_entity(workbench_uri)
            local entity_forms=workbench:get_component('stonehearth:entity_forms')
            local ghost_entity=entity_forms:get_ghost_entity()
            ghost_entity:add_component('stonehearth:commands'):remove_command('move_item')
            radiant.terrain.place_entity(ghost_entity,location)
            citizen:get_component('stonehearth:crafter'):create_workshop(ghost_entity,location)
        end

        -- place an entity at location
        function NewGameCallHandler:place_entity(uri, location, options)
            local entity = radiant.entities.create_entity(uri)
            radiant.terrain.place_entity(entity, location, options)
            return entity
        end

        function NewGameCallHandler:place_citizen(pop,x,z,job,talisman)
            local citizen=pop:create_new_citizen()
            if not job then
                job='stonehearth:jobs:worker'
            end
            pop:promote_citizen(citizen,job,talisman)
            radiant.terrain.place_entity(citizen,Point3(x,1,z))
            return citizen
        end
        function NewGameCallHandler:place_item(pop,uri,x,z,options)
            local entity=radiant.entities.create_entity(uri)
            radiant.terrain.place_entity(entity,Point3(x,1,z),options)
            entity:add_component('unit_info'):set_player_id(pop:get_player_id())
            return entity
        end
        function NewGameCallHandler:get_town_name(session,response)
            local town=stonehearth.town:get_town(session.player_id)
            if town then
                return
                {
                    townName=town:get_town_name()
                }
                
            else
                return
                {
                    townName='Defaultville'
                }
                
            end
        end
        function NewGameCallHandler:get_town_entity(session,response)
            local town=stonehearth.town:get_town(session.player_id)
            local entity=town:get_entity()
            return
            {
                town=entity
            }
            
        end
        function NewGameCallHandler:set_town_name(session,response,town_name)
            local town=stonehearth.town:get_town(session.player_id)
            town:set_town_name(town_name)
            return true
        end
        return NewGameCallHandler
