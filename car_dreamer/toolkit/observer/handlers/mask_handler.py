import numpy as np
from .base_handler import BaseHandler

class MaskHandler(BaseHandler):
    def __init__(self, world, config):
        super().__init__(world, config)
        self._height = config.shape[0]
        self._width = config.shape[1]
        self._sight_fov = config.sight_fov
        self._ego_offset = config.get('ego_offset', self._height - 1)

    def reset(self):
        pass

    def get_observation(self, env_state):
        mask = np.zeros((self._height, self._width), dtype=np.float32)
        center_x = self._width // 2

        for y in range(self._height):
            for x in range(self._width):
                dx = x - center_x
                dy = self._ego_offset - y
                
                if dy > 0:
                    angle = np.degrees(np.arctan2(dx, dy))
                    if abs(angle) < self._sight_fov / 2:
                        mask[y, x] = 1.0
        
        return mask[..., np.newaxis], {}
