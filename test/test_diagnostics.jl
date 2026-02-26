@testset "diagnostics" begin
    obj = Ref([1, 2, 3])

    task = Parables.@task "t1" begin
        Parables.@access obj Write() Block(1:2)
        obj[][1] = 2
    end

    acc = task.accesses[1]
    acc_str = sprint(show, acc)
    println("access: ", acc_str)
    @test occursin("Write", acc_str)
    @test occursin("Block(1:2)", acc_str)

    task_str = sprint(show, task)
    println("task: ", task_str)
    @test occursin("t1", task_str)
    @test occursin("Write", task_str)
    @test occursin("Block(1:2)", task_str)

    other_task = Parables.@task "t2" begin
        Parables.@access obj Read() Block(2:3)
    end

    conflict = explain_conflict(task, other_task)
    println("conflict: ", conflict)
    @test conflict !== nothing

    dag = Parables.@dag begin
        Parables.@spawn task
        Parables.@spawn other_task
    end

    dag_str = sprint(io -> print_dag(dag; io=io))
    println(dag_str)
    @test occursin("DAG with", dag_str)
    @test occursin("Levels:", dag_str)
end
