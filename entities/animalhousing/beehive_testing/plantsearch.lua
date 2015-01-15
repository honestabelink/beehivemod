local plantsearch = class()

function  plantsearch.onfound(searching_entity, entity)
	if entity:get_component("unit_info") then
		entity:get_component("unit_info"):set_display_name("bob")
	end
end

return plantsearch