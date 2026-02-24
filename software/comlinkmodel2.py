import random
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

# --- 严格对齐你提供的样式设置，部分字体放大 ---
plt.rcParams['font.size'] = 30
plt.rcParams['axes.linewidth'] = 0.7
plt.rcParams['xtick.direction'] = 'in'
plt.rcParams['ytick.direction'] = 'in'
plt.rcParams['xtick.major.size'] = 2.5
plt.rcParams['ytick.major.size'] = 2.5

# 坐标轴刻度数字放大
plt.rcParams['xtick.labelsize'] = 14
plt.rcParams['ytick.labelsize'] = 14


def run_remu_simulation():
    # 参数设置
    total_requests = 10000
    cache_sizes = [256, 128, 64]
    random.seed(42)

    # 模拟链路局部性 (Zipf 分布)
    possible_states = [round(random.uniform(10, 1000), 2) for _ in range(500)]
    weights = [1.0 / (i + 1) for i in range(len(possible_states))]
    request_sequence = random.choices(possible_states, weights=weights, k=total_requests)

    def get_model_calls(size):
        if size == 0: return total_requests
        cache = set()
        cache_order = []
        misses = 0
        for dist in request_sequence:
            if dist in cache:
                cache_order.remove(dist)
                cache_order.append(dist)
            else:
                misses += 1
                if len(cache) >= size:
                    oldest = cache_order.pop(0)
                    cache.remove(oldest)
                cache.add(dist)
                cache_order.append(dist)
        return misses

    # --- 收集数据 ---
    results_data = []
    # 这里为了适应变窄的图，给过长的标签增加了换行符 \n
    configs = [
        ("ReMu\n(256Entries)", 256, '#2ecc71'),
        ("ReMu\n(128Entries)", 128, '#3498db'),
        ("ReMu\n(64Entries)", 64, '#9b59b6'),
        ("Mininet", 0, '#e74c3c')
    ]

    for label, size, color in configs:
        calls = get_model_calls(size)
        results_data.append({'Label': label, 'Calls': calls, 'Color': color})

    df_plot = pd.DataFrame(results_data)

    # --- 绘图 ---
    # 图缩小，并且设置纵横比大约为 1:2 (宽3.5, 高7)
    fig, ax = plt.subplots(figsize=(12, 6))

    x_pos = np.arange(len(df_plot))
    bars = ax.bar(x_pos, df_plot['Calls'], color=df_plot['Color'],
                  edgecolor='black', linewidth=0.8, width=0.6, zorder=3)

    # 设置刻度
    ax.set_xticks(x_pos)

    # 因为图变窄了且字体变大，旋转X轴标签以防重叠
    ax.set_xticklabels(df_plot['Label'], ha='center',
                       fontstyle='normal')

    # 坐标轴标题放大
    ax.set_ylabel('Link Model Call Count', fontsize=24)
    ax.set_xlabel('Methods', fontsize=24)

    for label in ax.get_xticklabels():
        label.set_fontsize(24)


        for label in ax.get_yticklabels():
            label.set_fontsize(24)


    # --- 纵坐标调整 ---
    ax.set_ylim(0, total_requests * 1.1)
    ax.set_yticks(np.arange(0, total_requests + 1, 2000))

    # 网格线
    ax.grid(True, axis='y', linestyle='-', alpha=0.5, linewidth=0.6, color='gray')
    ax.set_axisbelow(True)

    # 数值标注 (柱子上方数字也适当放大)
    for bar in bars:
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2., height + 150,
                f'{int(height)}', ha='center', va='bottom',
                fontsize=24, )

    # 移除顶部和右侧边框
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    # 保存 PDF
    plt.savefig('comlinkmodel.pdf', format='pdf', bbox_inches='tight')
    plt.show()


if __name__ == "__main__":
    run_remu_simulation()