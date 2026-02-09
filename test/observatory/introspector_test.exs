defmodule Observatory.IntrospectorTest do 
  use ExUnit.Case, async: true

  alias Observatory.Introspector 

  describe "tests for analyze/1" do
    test "test analyze/1 with valid file path" do
      assert {:ok, _} = Introspector.analyze("/home/ongera/Music/adjusted_rap_vocals.wav")
    end

    test "test analyze/1 with invalid path" do
      assert {:error, _} = Introspector.analyze("/home/ongera/Music/rap_vocals.wav")
    end
  end

  describe "test for ffbrobe related functions" do
    test "test ffprobe_available?/1" do
      assert :true = Introspector.ffprobe_available?(["-version"])
    end 
  end


end
