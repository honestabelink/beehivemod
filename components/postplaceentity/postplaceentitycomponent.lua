local PostPlaceEntityComponent=class()
function PostPlaceEntityComponent:initialize(entity,json)
    self._entity=entity
    if self._sv._initialized then
        radiant.events.listen_once(radiant,'radiant:game_loaded',
        function(e)
            
        end)
    else
        self.__saved_variables:mark_changed()
        radiant.events.listen_once(entity,'radiant:entity:post_create',
        function()
            
        end)
    end
end
