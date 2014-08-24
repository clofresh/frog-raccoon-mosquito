WIDTH, HEIGHT = 1024, 768
PPM = 50
GRAVITY = 1000.0
love.window.setMode(WIDTH, HEIGHT)

world = nil
ground = nil

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

function love.load()
    sounds = {
        ribbit = love.audio.newSource('audio/ribbit.ogg')
    }

    world = love.physics.newWorld(0, 0, false)
    love.physics.setMeter(PPM)
    frog = {
        body = love.physics.newBody(world, 20, 100, 'dynamic'),
        shape = love.physics.newCircleShape(20),
        speed = 80,
        dir = 1,
        grounded = false,
        croakCooldown = 0,
        img = love.graphics.newImage('img/frog.png'),
        ox = 30,
        oy = 40,
    }
    frog.fixture = love.physics.newFixture(frog.body, frog.shape)
    frog.fixture:setSensor(true)
    frog.fixture:setUserData(frog)
    frog.jump = {airTime = 0}
    function frog.jump:update(dt)
        self.state(self, dt)
    end
    function frog.jump:ready(dt)
        if love.keyboard.isDown(' ') and frog.grounded then
            self.state = self.charging
            self.chargeTimer = 0
        end
    end
    function frog.jump:charging(dt)
        self.chargeTimer = self.chargeTimer + dt
        if not love.keyboard.isDown(' ') and frog.grounded then
            self.co = jumpCoroutine(frog, math.min(self.chargeTimer * 500, 500))
            self.state = self.jumping
            self.airTime = 0
        end
    end
    function frog.jump:jumping(dt)
        self.airTime = self.airTime + dt
        if coroutine.status(self.co) == 'dead' then
            frog.body:setLinearVelocity(0, 0)
            self.state = self.ready
            self.co = nil
        else
            coroutine.resume(self.co, dt)
        end
    end
    frog.jump.co = jumpCoroutine(frog, 0)
    frog.jump.state = frog.jump.jumping
    function frog:startCollision(myFixture, otherFixture, contact)
        local other = otherFixture:getUserData()
        if other.type == 'mosquito' then
            other.eaten = true
        end
    end

    mosquitoes = {}
    mosquitoSpawnCooldown = 0
    mosquitoBatch = love.graphics.newSpriteBatch(love.graphics.newImage('img/mosquito.png'))

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
        if objA.startCollision then
            objA:startCollision(fixtureA, fixtureB, contact)
        end
        if objB.startCollision then
            objB:startCollision(fixtureB, fixtureA, contact)
        end
    end,
    function(fixtureA, fixtureB, contact)
        local objA = fixtureA:getUserData()
        local objB = fixtureB:getUserData()
        if objA.endCollision then
            objA:endCollision(fixtureA, fixtureB, contact)
        end
        if objB.endCollision then
            objB:endCollision(fixtureB, fixtureA, contact)
        end
    end)
end

function love.update(dt)
    if mosquitoSpawnCooldown > 0 then
        mosquitoSpawnCooldown = math.max(0, mosquitoSpawnCooldown - dt)
    end
    if #mosquitoes < 20 and mosquitoSpawnCooldown <= 0 then
        mosquitoSpawnCooldown = 1.0
        local mosquito = {
            type = 'mosquito',
            body = love.physics.newBody(world, math.random(100, 1948), math.random(100, 500), 'dynamic'),
            shape = love.physics.newCircleShape(10),
            r = 0,
            speed = {
                x = 500,
                y = 200,
            }
        }
        mosquito.fixture = love.physics.newFixture(mosquito.body, mosquito.shape)
        mosquito.fixture:setUserData(mosquito)
        table.insert(mosquitoes, mosquito)
    end
    local newMosquitoes = {}
    mosquitoBatch:clear()
    for i, mosquito in pairs(mosquitoes) do
        if not mosquito.eaten then
            mosquito.body:setLinearVelocity(math.random(-mosquito.speed.x, mosquito.speed.x) * math.cos(mosquito.r), math.random(-mosquito.speed.y, mosquito.speed.y) * math.sin(mosquito.r))
            mosquito.r = mosquito.r + math.pi * dt
            local x, y = mosquito.body:getPosition()
            mosquitoBatch:add(x, y, 0, 1, 1, 8, 6)
            table.insert(newMosquitoes, mosquito)
        end
    end
    mosquitoes = newMosquitoes

    frog.jump:update(dt)
    if love.keyboard.isDown('a', 'd') then
        if love.keyboard.isDown('a') then
            frog.dir = -1
        elseif love.keyboard.isDown('d') then
            frog.dir = 1
        end
    end
    if frog.croakCooldown > 0 then
        frog.croakCooldown = math.max(0, frog.croakCooldown - dt)
    end
    if love.keyboard.isDown('r') and frog.croakCooldown <= 0 and frog.grounded then
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
    cx = math.max(math.min(0, WIDTH / 2 - x), WIDTH - 2048)
    cy = math.max(HEIGHT / 2 - y, 0)

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
    love.graphics.translate(cx, cy)

    -- sky
    love.graphics.setColor(255, 255, 255)
    love.graphics.draw(sky.batch, 0, 768 - 1500)

    -- water
    -- love.graphics.setColor(water.color)
    -- local wx, wy = water.body:getPosition()
    -- love.graphics.polygon('fill', wx, wy, water.body:getWorldPoints(water.shape:getPoints()))
    love.graphics.draw(water.batch, water.body:getPosition())

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
    love.graphics.draw(frog.img, x, y, 0, frog.dir, 1, frog.ox, frog.oy)
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
end
