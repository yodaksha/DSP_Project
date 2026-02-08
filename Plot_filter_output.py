
"""
Plot FIR Filter Input and Output
"""

import matplotlib.pyplot as plt
import numpy as np

def read_data_file(filename):
    
    data = []
    try:
        with open(filename, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    data.append(int(line))
    except FileNotFoundError:
        print(f"Error: {filename} not found")
        return None
    return np.array(data)

def main():
    # Read input and output data
    input_data = read_data_file('input32.txt')
    output_actual = read_data_file('output_actual.txt')
    output_ref = read_data_file('output_ref32.txt')
    
    if input_data is None or output_actual is None:
        return
    
    # Create figure with subplots
    fig, axes = plt.subplots(3, 1, figsize=(14, 10))
    
    # Plot 1: Input Signal
    axes[0].plot(input_data, 'b-', linewidth=1, label='Input Signal')
    axes[0].set_xlabel('Sample Index')
    axes[0].set_ylabel('Amplitude')
    axes[0].set_title('FIR Filter Input Signal')
    axes[0].grid(True, alpha=0.3)
    axes[0].legend()
    
    # Plot 2: Filtered Output (Hardware vs Reference)
    axes[1].plot(output_actual, 'r-', linewidth=1.5, label='Hardware Output', alpha=0.8)
    if output_ref is not None:
        axes[1].plot(output_ref[:len(output_actual)], 'g--', linewidth=1, label='MATLAB Reference', alpha=0.6)
    axes[1].axhline(y=32767, color='k', linestyle='--', alpha=0.3, label='Saturation Limits')
    axes[1].axhline(y=-32768, color='k', linestyle='--', alpha=0.3)
    axes[1].set_xlabel('Sample Index')
    axes[1].set_ylabel('Amplitude')
    axes[1].set_title('FIR Filter Output (16-bit Signed)')
    axes[1].grid(True, alpha=0.3)
    axes[1].legend()
    
    # Plot 3: Error
    if output_ref is not None:
        min_len = min(len(output_actual), len(output_ref))
        error = output_ref[:min_len] - output_actual[:min_len]
        axes[2].plot(error, 'm-', linewidth=1, label='Error (Ref - HW)')
        axes[2].set_xlabel('Sample Index')
        axes[2].set_ylabel('Error')
        axes[2].set_title('Output Error (Due to Saturation)')
        axes[2].grid(True, alpha=0.3)
        axes[2].legend()
        
        # Calculate statistics
        num_saturated = np.sum((output_actual == 32767) | (output_actual == -32768))
        num_matches = np.sum(error == 0)
        print(f"\nStatistics:")
        print(f"  Total samples:       {min_len}")
        print(f"  Exact matches:       {num_matches} ({100*num_matches/min_len:.1f}%)")
        print(f"  Saturated outputs:   {num_saturated} ({100*num_saturated/min_len:.1f}%)")
        print(f"  Mean absolute error: {np.mean(np.abs(error)):.2f}")
        print(f"  Max error:           {np.max(np.abs(error))}")
    
    plt.tight_layout()
    plt.savefig('filter_output_plot.png', dpi=150, bbox_inches='tight')
    print(f"\nPlot saved as: filter_output_plot.png")
    plt.show()

if __name__ == '__main__':
    main()
