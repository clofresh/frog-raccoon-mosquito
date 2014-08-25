WIDTH, HEIGHT = 1024, 768
PPM = 50
GRAVITY = 1000.0
love.window.setMode(WIDTH, HEIGHT)

world = nil
ground = nil
playerControl = nil

function jumpCoroutine(obj, height)
    local initalSpeed = -math.sqrt(2 * GRAVITY * height)
    local duration = -2 * initalSpeed / GRAVITY
    obj.body:setLinearVelocity(-obj.dir * initalSpeed, initalSpeed)
    return coroutine.create(function()
        local dt, vy, xn, xy, fraction, x, y
        local timer = 0
        while timer < 0.1 or not obj.grounded do
            dt = coroutine.yield()
            timer = timer + dt
            vy = GRAVITY * timer + initalSpeed
            obj.body:setLinearVelocity(-obj.dir * initalSpeed, vy)

            x, y = obj.body:getPosition()
            rx1 = x
            ry1 = math.min(ground.body:getY() - 1, y)
            rx2 = x
            ry2 = ry1 + obj.shape:getRadius() / 2
            local gx, gy = ground.body:getPosition()
            xn, xy, fraction = ground.shape:rayCast(rx1, ry1, rx2, ry2, 1, gx, gy, 0)
            obj.grounded = xn ~= nil
        end
    end)
end

function newFrog()
    local frog = {
        type = 'frog',
        body = love.physics.newBody(world, 20, 100, 'dynamic'),
        shape = love.physics.newCircleShape(20),
        speed = 80,
        dir = 1,
        grounded = false,
        croakCooldown = 0,
        img = love.graphics.newImage('img/frog.png'),
        ox = 30,
        oy = 40,
        sy = 1,
    }
    frog.fixture = love.physics.newFixture(frog.body, frog.shape)
    frog.fixture:setSensor(true)
    frog.fixture:setUserData(frog)
    frog.jump = {
        airTime = 0,
        readyCooldown = 0,
    }
    function frog.jump:update(dt)
        self.state(self, dt)
    end
    function frog.jump:ready(dt)
        if self.readyCooldown >= 0 then
            self.readyCooldown = math.max(0, self.readyCooldown - dt)
        end
        if frog.grounded and
            (playerControl == frog and love.keyboard.isDown(' ')) or
            (playerControl ~= frog and self.readyCooldown <= 0)
        then
            self.state = self.charging
            self.chargeTimer = 0
            if playerControl ~= frog then
                self.chargeDuration = math.random(1, 10) / 10.0
            end
        end
    end
    function frog.jump:charging(dt)
        self.chargeTimer = self.chargeTimer + dt
        frog.sy = math.max(0.75, frog.sy - dt/5)
        if frog.grounded and
            (playerControl == frog and not love.keyboard.isDown(' ')) or
            (playerControl ~= frog and self.chargeTimer >= self.chargeDuration) then
            self.co = jumpCoroutine(frog, math.min(self.chargeTimer * 500, 500))
            self.state = self.jumping
            self.airTime = 0
            frog.sy = 1
        end
    end
    function frog.jump:jumping(dt)
        self.airTime = self.airTime + dt
        if coroutine.status(self.co) == 'dead' then
            frog.body:setLinearVelocity(0, 0)
            self.state = self.ready
            self.co = nil
            if playerControl ~= frog then
                self.readyCooldown = math.random(0, 10) / 10.0
                if math.random() > 0.5 then
                    frog.dir = 1
                else
                    frog.dir = -1
                end
            end
        else
            coroutine.resume(self.co, dt)
        end
    end
    frog.jump.co = jumpCoroutine(frog, 0)
    frog.jump.state = frog.jump.jumping
    function frog:startCollision(myFixture, otherFixture, contact)
        local other = otherFixture:getUserData()
        if other and other.type == 'mosquito' then
            other.eaten = true
            if playerControl == other then
                print('eaten by the frog')
                switchControl(frog)
            elseif playerControl == frog then
                print('ate a mosquito')
                score.mosquitoes = score.mosquitoes + 1
            end
        end
    end
    return frog
end

function love.load()
    score = {
        frogs = 0,
        racoons = 0,
        mosquitoes = 0,
    }
    sounds = {
        ribbit = love.audio.newSource('audio/ribbit.ogg')
    }

    world = love.physics.newWorld(0, 0, false)
    love.physics.setMeter(PPM)
    frog = newFrog()

    mosquitoes = {}
    for i = 1, 10 do
        table.insert(mosquitoes, newMosquito())
    end
    mosquitoSpawnCooldown = 0
    mosquitoBatch = love.graphics.newSpriteBatch(love.graphics.newImage('img/mosquito.png'))

    racoons = {}
    for i = 1, 3 do
        table.insert(racoons, newRacoon())
    end
    racoonSpawnCooldown = 0
    racoonBatch = love.graphics.newSpriteBatch(love.graphics.newImage('img/racoon.png'))

    ground = {
        body = love.physics.newBody(world, 0, 585, 'static'),
        shape = love.physics.newPolygonShape(-1024, 0, 2048, 0, 2048, 250, -1024, 250),
        img = love.graphics.newImage('img/ground.png')
    }
    ground.body:setFixedRotation(true)
    ground.fixture = love.physics.newFixture(ground.body, ground.shape)
    ground.fixture:setUserData(ground)
    ground.batch = love.graphics.newSpriteBatch(ground.img)
    local imgWidth = ground.img:getWidth()
    for i = 0, 9 do
        ground.batch:add(i * imgWidth, 0)
    end

    boundaries = {
        {
            type = 'boundary',
            body = love.physics.newBody(world, 0, 0, 'static'),
            shape = love.physics.newRectangleShape(200, 2048),
        },
        {
            type = 'boundary',
            body = love.physics.newBody(world, 1948, 0, 'static'),
            shape = love.physics.newRectangleShape(200, 2048),
        },
    }
    for i, b in pairs(boundaries) do
        b.fixture = love.physics.newFixture(b.body, b.shape)
        b.fixture:setSensor(true)
        b.fixture:setUserData(b)
    end

    water = {
        body = love.physics.newBody(world, 0, 550, 'static'),
        shape = love.physics.newPolygonShape(0, 0, 2048, 0, 2048, 400, 0, 400),
        color = {38, 166, 141},
        img = love.graphics.newImage('img/water.png'),
        splashes = {},
    }
    water.body:setFixedRotation(true)
    water.fixture = love.physics.newFixture(water.body, water.shape)
    water.fixture:setUserData(water)
    water.fixture:setSensor(true)
    water.batch = love.graphics.newSpriteBatch(water.img)
    local imgWidth = water.img:getWidth()
    for i = 0, 9 do
        water.batch:add(i * imgWidth, 0)
    end
    water.particleSystem = love.graphics.newParticleSystem(love.graphics.newImage('img/drop.png'), 20)
    water.particleSystem:setEmitterLifetime(0.25)
    water.particleSystem:setEmissionRate(100)
    water.particleSystem:setAreaSpread('normal', 10, 5)
    water.particleSystem:setColors(255, 255, 255, 255, 255, 255, 255, 0)
    water.particleSystem:setParticleLifetime(0.25)
    water.particleSystem:setSizes(0.25, 0.5, 0)
    water.particleSystem:setSizeVariation(0.5)

    sky = {
        img = love.graphics.newImage('img/sky.png')
    }
    sky.batch = love.graphics.newSpriteBatch(sky.img)
    local imgWidth = sky.img:getWidth()
    for i = 0, 9 do
        sky.batch:add(i * imgWidth - (i), 0)
    end

    function water:startCollision(myFixture, otherFixture, contact)
        local splash = water.particleSystem:clone()
        splash:setPosition(otherFixture:getBody():getX(), water.body:getY())
        splash:setLinearAcceleration(0, 0, 0, 800)
        splash:start()
        table.insert(water.splashes, splash)
    end
    function water:endCollision(myFixture, otherFixture, contact)
        local splash = water.particleSystem:clone()
        splash:setPosition(otherFixture:getBody():getX(), water.body:getY())
        splash:setLinearAcceleration(0, -800, 0, 0)
        splash:start()
        table.insert(water.splashes, splash)
    end

    world:setCallbacks(function(fixtureA, fixtureB, contact)
        local objA = fixtureA:getUserData() 
        local objB = fixtureB:getUserData()
        if objA and objA.startCollision then
            objA:startCollision(fixtureA, fixtureB, contact)
        end
        if objB and objB.startCollision then
            objB:startCollision(fixtureB, fixtureA, contact)
        end
    end,
    function(fixtureA, fixtureB, contact)
        local objA = fixtureA:getUserData()
        local objB = fixtureB:getUserData()
        if objA and objA.endCollision then
            objA:endCollision(fixtureA, fixtureB, contact)
        end
        if objB and objB.endCollision then
            objB:endCollision(fixtureB, fixtureA, contact)
        end
    end)

    switchControl(frog)
end

mosquitoFlying = {}

function mosquitoStartCollision(self, meFixture, otherFixture, contact)
    local otherObj = otherFixture:getUserData()
    if otherObj and otherObj.type == 'racoon' and not otherObj.stealth then
        otherObj.eaten = true
        if playerControl == otherObj then
            switchControl(self)
        elseif playerControl == self then
            score.racoons = score.racoons + 1
        end
    end
end

function newMosquito()
    local mosquito = {
        type = 'mosquito',
        body = love.physics.newBody(world, math.random(100, 1948), math.random(100, 500), 'dynamic'),
        shape = love.physics.newCircleShape(10),
        r = 0,
        speed = {
            x = 500,
            y = 200,
        },
        state = mosquitoFlying.idle
    }
    mosquito.fixture = love.physics.newFixture(mosquito.body, mosquito.shape)
    mosquito.fixture:setUserData(mosquito)
    mosquito.fixture:setSensor(true)
    mosquito.flyCooldown = math.random(10, 20) / 10.0
    mosquito.startCollision = mosquitoStartCollision
    return mosquito
end

function mosquitoFlying.idle(mosquito, dt)
    if (playerControl ~= mosquito and mosquito.flyCooldown > 0) or
    (playerControl == mosquito and not love.keyboard.isDown(' ')) then
        mosquito.flyCooldown = math.max(0, mosquito.flyCooldown - dt)
        mosquito.body:setLinearVelocity(math.random(-mosquito.speed.x, mosquito.speed.x) * math.cos(mosquito.r), math.random(-mosquito.speed.y, mosquito.speed.y) * math.sin(mosquito.r))
        mosquito.r = mosquito.r + math.pi * dt
    elseif (playerControl ~= mosquito and mosquito.flyCooldown <= 0) or
        (playerControl == mosquito and love.keyboard.isDown(' ')) then
        mosquito.state = mosquitoFlying.fly
        local speed = 1000
        if playerControl == mosquito then
            local dx = 0
            local dy = 0
            if love.keyboard.isDown('a') then
                dx = -1
            elseif love.keyboard.isDown('d') then
                dx = 1
            end
            if love.keyboard.isDown('w') then
                dy = -1
            elseif love.keyboard.isDown('s') then
                dy = 1
            end
            mosquito.r = math.atan2(dy, dx)
        else
            if mosquito.body:getY() < 500 then
                mosquito.r = math.random(0, math.pi*100)/100.0
            else
                mosquito.r = math.pi + math.random(0, math.pi*100)/100.0
            end
        end
        mosquito.body:setLinearVelocity(speed * math.cos(mosquito.r), speed * math.sin(mosquito.r))
        mosquito.flyCooldown = math.random(10, 20) / 10.0
    end
end

function mosquitoFlying.fly(mosquito, dt)
    if mosquito.flyCooldown > 0 then
        mosquito.flyCooldown = math.max(0, mosquito.flyCooldown - dt)
    else
        mosquito.state = mosquitoFlying.idle
        mosquito.flyCooldown = math.random(10, 20) / 10.0
    end
end

racoonHunting = {}
function racoonHunting.hunting(racoon, dt)
    if racoon.huntingCo then
        if coroutine.status(racoon.huntingCo) == 'dead' then
            racoon.huntingCo = nil
            racoon.state = racoonHunting.movingOpen
            racoon.stealth = true
            if playerControl ~= racoon then
                racoon.body:setLinearVelocity(racoon.dir * 100, 0)
            end
        else
            coroutine.resume(racoon.huntingCo, dt)
        end
    else
        racoon.huntingCo = coroutine.create(function()
            local dt
            local x, y = racoon.body:getPosition()
            local lx, ly = unpack(racoon.lastSeen)
            local timer = 0
            racoon.claws = {x, y, lx, ly}
            while timer < 0.25 do
                dt = coroutine.yield()
                timer = timer + dt

            end
            world:rayCast(x, y, lx, ly,
                function(fixture, x, y, xn, yn, fraction)
                    if fixture == racoon.fixture then
                        return -1
                    else
                        local obj = fixture:getUserData() or {}
                        if obj.type == 'frog' then
                            print('hit frog!')
                            if playerControl == frog then
                                switchControl(racoon)
                            elseif playerControl == racoon then
                                score.frogs = score.frogs + 1
                            end
                            frog.eaten = true
                            frog.jump.readyCooldown = 0
                            racoon.stealth = true
                            racoon.lastSeen = nil
                            racoon.huntingCo = nil
                            racoon.state = racoonHunting.movingOpen
                            if playerControl ~= racoon then
                                racoon.body:setLinearVelocity(racoon.dir * 100, 0)
                            end
                            return 0
                        end
                    end
                    return -1
                end)
            racoon.claws = nil
            timer = 0
            while timer < 0.25 do
                dt = coroutine.yield()
                timer = timer + dt
            end
        end)
    end
end

function racoonHunting.enteringStealth()
end

function racoonHunting.exitingStealth()
end

function racoonHunting.movingStealth()
end

function racoonHunting.movingOpen(racoon, dt)
    local x, y = racoon.body:getPosition()
    if playerControl == racoon then
        if love.keyboard.isDown('a', 'd') then
            if love.keyboard.isDown('a') then
                racoon.dir = -1
            else
                racoon.dir = 1
            end
            racoon.body:setLinearVelocity(racoon.dir * 100, 0)
        else
            if love.keyboard.isDown(' ') then
                racoon.stealth = false
                racoon.state = racoonHunting.hunting
                racoon.lastSeen = {x + racoon.dir * 50, y + 60}
            end
            racoon.body:setLinearVelocity(0, 0)
        end
    else
        world:rayCast(x, y, x + racoon.dir * 50, y + 60,
            function(fixture, x, y, xn, yn, fraction)
                if fixture == racoon.fixture then
                    return -1
                else
                    local obj = fixture:getUserData() or {}
                    if obj.type == 'boundary' then
                        racoon.dir = racoon.dir * -1
                        racoon.body:setLinearVelocity(racoon.dir * 100, 0)
                        return 0
                    elseif obj.type == 'frog' then
                        racoon.stealth = false
                        racoon.state = racoonHunting.hunting
                        racoon.body:setLinearVelocity(0, 0)
                        racoon.lastSeen = {obj.body:getPosition()}
                        return 0
                    else
                        return -1
                    end
                end
            end)
    end
end

function newRacoon()
    local racoon = {
        type = 'racoon',
        body = love.physics.newBody(world, math.random(100, 1948), 510, 'dynamic'),
        shape = love.physics.newCircleShape(30),
        dir = 1,
        ox = 64,
        oy = 86,
        stealth = true,
    }
    racoon.fixture = love.physics.newFixture(racoon.body, racoon.shape)
    racoon.fixture:setUserData(racoon)
    racoon.fixture:setSensor(true)
    racoon.state = racoonHunting.movingOpen
    racoon.body:setLinearVelocity(racoon.dir * 100, 0)
    return racoon
end

function switchControl(obj)
    playerControl = obj
end

function love.update(dt)
    if mosquitoSpawnCooldown > 0 then
        mosquitoSpawnCooldown = math.max(0, mosquitoSpawnCooldown - dt)
    end
    if #mosquitoes < 20 and mosquitoSpawnCooldown <= 0 then
        mosquitoSpawnCooldown = 1.0
        table.insert(mosquitoes, newMosquito())
    end
    local newMosquitoes = {}
    mosquitoBatch:clear()
    for i, mosquito in pairs(mosquitoes) do
        if mosquito.eaten then
            mosquito.fixture:destroy()
        else
            mosquito.state(mosquito, dt)
            local x, y = mosquito.body:getPosition()
            local newX, newY
            if x < 0 or x > 2048 then
                newX = math.min(math.max(0, x), 2048)
                x = newX
            end
            if y < 0 or y > 510 then
                newY = math.min(math.max(0, y), 510)
                y = newY
            end
            if newX or newY then
                mosquito.body:setPosition(newX or x, newY or y)
            end
            mosquitoBatch:add(x, y, 0, 1, 1, 8, 6)

            if playerControl == mosquito then
                cx = math.max(math.min(0, WIDTH / 2 - x), WIDTH - 2048)
                cy = math.max(HEIGHT / 2 - y, 0)
            end

            table.insert(newMosquitoes, mosquito)
        end
    end
    mosquitoes = newMosquitoes

    if racoonSpawnCooldown > 0 then
        racoonSpawnCooldown = math.max(0, racoonSpawnCooldown - dt)
    end
    if #racoons < 3 and racoonSpawnCooldown <= 0 then
        racoonSpawnCooldown = 5.0
        table.insert(racoons, newRacoon())
    end

    local newRacoons = {}
    racoonBatch:clear()
    for i, racoon in pairs(racoons) do
        if racoon.eaten then
            racoon.fixture:destroy()
        else
            racoon.state(racoon, dt)
            local x, y = racoon.body:getPosition()
            if racoon.stealth then
                racoonBatch:setColor(255, 255, 255, 64)
            else
                racoonBatch:setColor()
            end
            racoonBatch:add(x, y, 0, racoon.dir, 1, racoon.ox, racoon.oy)
            table.insert(newRacoons, racoon)
            if playerControl == racoon then
                cx = math.max(math.min(0, WIDTH / 2 - x), WIDTH - 2048)
                cy = math.max(HEIGHT / 2 - y, 0)
            end
        end
    end
    racoons = newRacoons

    if frog.eaten then
        frog.fixture:destroy()
        frog = newFrog()
    end

    frog.jump:update(dt)
    if playerControl == frog then
        if love.keyboard.isDown('a', 'd') then
            if love.keyboard.isDown('a') then
                frog.dir = -1
            elseif love.keyboard.isDown('d') then
                frog.dir = 1
            end
        end
    end
    if frog.croakCooldown > 0 then
        frog.croakCooldown = math.max(0, frog.croakCooldown - dt)
    end
    if playerControl == frog and love.keyboard.isDown('r') and frog.croakCooldown <= 0 and frog.grounded then
        frog.croakCooldown = 0.5
        love.audio.rewind(sounds.ribbit)
        love.audio.play(sounds.ribbit)
    end
    local x, y = frog.body:getPosition()
    local newX
    if x < 0 or x > 2040 then
        x = math.min(math.max(0, x), 2040)
        frog.body:setPosition(x, y)
    end
    if y > HEIGHT then
        frog.body:setPosition(x, 100)
        frog.body:setLinearVelocity(0, 0)
        frog.jump.state = frog.jump.jumping
        frog.jump.co = jumpCoroutine(frog, 0)
    end

    if playerControl == frog then
        cx = math.max(math.min(0, WIDTH / 2 - x), WIDTH - 2048)
        cy = math.max(HEIGHT / 2 - y, 0)
    end

    local newSplashes = {}
    for i, splash in pairs(water.splashes) do
        splash:update(dt)
        if splash:isActive() then
            table.insert(newSplashes, splash)
        end
    end

    world:update(dt)
end

function love.draw()
    love.graphics.setBackgroundColor(1, 52, 103)

    love.graphics.push()
    love.graphics.translate(cx, cy)

    -- sky
    love.graphics.setColor(255, 255, 255)
    love.graphics.draw(sky.batch, 0, 768 - 1500)

    -- water
    -- love.graphics.setColor(water.color)
    -- local wx, wy = water.body:getPosition()
    -- love.graphics.polygon('fill', wx, wy, water.body:getWorldPoints(water.shape:getPoints()))
    love.graphics.draw(water.batch, water.body:getPosition())

    -- racoons
    love.graphics.draw(racoonBatch)
    love.graphics.setColor(0, 0, 0)
    for i, racoon in pairs(racoons) do
        local x, y = racoon.body:getPosition()
        -- love.graphics.circle('line', x, y, racoon.shape:getRadius())
        -- love.graphics.line(x, y, x + racoon.dir * 50, y + 60)
        if racoon.claws then
            love.graphics.setColor(255, 0, 0)
            love.graphics.line(unpack(racoon.claws))
            love.graphics.setColor(0, 0, 0)
        end
    end
    love.graphics.setColor(255, 255, 255)

    -- mosquitoes
    love.graphics.draw(mosquitoBatch)
    -- love.graphics.setColor(0, 0, 0)
    -- for i, mosquito in pairs(mosquitoes) do
    --     local x, y = mosquito.body:getPosition()
    --     love.graphics.circle('line', x, y, mosquito.shape:getRadius())
    -- end
    -- love.graphics.setColor(255, 255, 255)


    -- frog
    local x, y = frog.body:getPosition()
    love.graphics.draw(frog.img, x, y, 0, frog.dir, frog.sy, frog.ox, frog.oy)
    -- love.graphics.setColor(0, 255, 0)
    -- love.graphics.circle('line', x, y, frog.shape:getRadius())


    -- ground
    love.graphics.setColor(255, 255, 255)
    love.graphics.draw(ground.batch, 0, 0)
    love.graphics.setColor(255, 0, 0)

    -- local gx, gy = ground.body:getPosition()
    -- love.graphics.polygon('line', gx, gy, ground.body:getWorldPoints(ground.shape:getPoints()))

    -- love.graphics.line(rx1, ry1, rx2, ry2)

    for i, splash in pairs(water.splashes) do
        love.graphics.draw(splash)
    end

    -- love.graphics.setColor(0, 0, 0)
    -- for i, b in pairs(boundaries) do
    --     local x, y = b.body:getPosition()
    --     love.graphics.polygon('line', x, y, b.body:getWorldPoints(b.shape:getPoints()))
    -- end

    love.graphics.pop()
    local y = 20
    love.graphics.setColor(255, 255, 255)
    for type, val in pairs(score) do
        love.graphics.print(string.format('%s: %d', type, val), 20, y)
        y = y + 20
    end

end
