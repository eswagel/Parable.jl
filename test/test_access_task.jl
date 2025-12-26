@testset "access and task" begin
    obj = Ref(1)

    acc = access(obj, Read(), Whole())
    @test acc.objid == objectid(obj)
    @test acc.obj === obj
    @test isa(acc.eff, Read)
    @test isa(acc.reg, Whole)

    @test objkey(obj) == (objectid(obj), obj)

    t = TaskSpec("t", () -> nothing)
    @test isempty(t.accesses)

    add_access!(t, obj, Write(), Whole())
    @test length(t.accesses) == 1
    @test isa(t.accesses[1].eff, Write)
    @test isa(t.accesses[1].reg, Whole)
end
