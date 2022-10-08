LibLootStats.utils = {
    Bind = function(self, fn) return function(...) return fn(self, ...) end end,
    Closure = function(self, fn) return function(_, ...) return fn(self, ...) end end,
}
