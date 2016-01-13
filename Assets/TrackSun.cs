using System;
using System.Collections.Generic;
using UnityEngine;

[RequireComponent(typeof(MeshRenderer))]
public class TrackSun : MonoBehaviour
{

    [Tooltip("The 'sun' position variable for this shader, or null")]
    public GameObject sun;

    /// Internal center id name
    Vector3 sunPos;
    private int sunId;
    private Renderer renders;

    public void Start()
    {
        if (sun != null)
        {
            sunId = Shader.PropertyToID("_sun");
        }
        renders = GetComponent<Renderer>();
    }

    public void Update()
    {
        if (sun != null)
        {
            var sp = sun.transform.position;
            if (sunPos != sp)
            {
                sunPos = sp;
                renders.material.SetVector(sunId, sp);
            }
        }
    }
}
