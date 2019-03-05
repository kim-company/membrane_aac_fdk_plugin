defmodule Membrane.Element.AAC.Decoder do
  use Membrane.Element.Base.Filter
  alias __MODULE__.Native
  alias Membrane.Buffer
  alias Membrane.Caps.Audio.Raw

  def_input_pads input: [
                   caps: :any,
                   demand_unit: :buffers
                 ]

  def_output_pads output: [
                    caps: {Raw, format: :s16le}
                  ]

  @impl true
  def handle_init(_) do
    {:ok, %{native: nil}}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, state) do
    with {:ok, native} <- Native.create() do
      {:ok, %{state | native: native}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_demand(:output, _size, :bytes, _ctx, state) do
    {{:ok, demand: :input}, state}
  end

  @impl true
  def handle_caps(:input, _caps, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, ctx, state) do
    with {:ok} <- Native.fill(payload, state.native),
         {:ok, decoded_frames} <- decode_buffer(payload, state.native),
         {:ok, caps_action} <- get_caps_if_needed(ctx.pads.output.caps, state) do
      buffer_actions = wrap_frames(decoded_frames)

      {{:ok, caps_action ++ buffer_actions ++ [redemand: :output]}, state}
    else
      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  defp decode_buffer(payload, native, acc \\ [])

  defp decode_buffer(payload, native, acc) do
    case Native.decode_frame(payload, native) do
      {:ok, decoded_frame} ->
        decode_buffer(payload, native, acc ++ [decoded_frame])

      {:error, :not_enough_bits} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wrap_frames([]), do: []

  defp wrap_frames(frames) do
    frame_buffers = frames |> Enum.map(fn frame -> %Buffer{payload: frame} end)
    [buffer: {:output, frame_buffers}]
  end

  defp get_caps_if_needed(nil, state) do
    {:ok, {_frame_size, sample_rate, channels}} = Native.get_metadata(state.native)
    {:ok, caps: {:output, %Raw{format: :s16le, sample_rate: sample_rate, channels: channels}}}
  end

  defp get_caps_if_needed(_, _), do: {:ok, []}
end
