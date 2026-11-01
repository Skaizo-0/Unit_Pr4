using System.Collections.Generic;
using UnityEngine;

public sealed class LookupExercise : MonoBehaviour
{
    public const int ItemCount = 4096;
    public const int QueryCount = 1024;

    private readonly struct Record
    {
        public readonly int Id;
        public readonly int Value;

        public Record(int id, int value)
        {
            Id = id;
            Value = value;
        }
    }

    private readonly Record[] records = new Record[ItemCount];
    private readonly Dictionary<int, int> index = new Dictionary<int, int>(ItemCount);

    private void Awake()
    {
        for (int id = 0; id < ItemCount; id++)
        {
            int value = id * 3 + 7;
            records[id] = new Record(id, value);
            index.Add(id, value);
        }
    }

    #region Practice 4.1 student hotspot: optimize ExecuteBatch, preserve all outputs
    public int ExecuteBatch(int[] queries, int[] results)
    {
        int checksum = 0;
        for (int query = 0; query < queries.Length; query++)
        {
            int value = index[queries[query]];
            results[query] = value;
            checksum += value;
        }
        return checksum;
    }
    #endregion
}
